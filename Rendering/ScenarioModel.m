classdef ScenarioModel < handle
    properties
        agents = []
        targets = Target.empty
        edges = Edge.empty
        walls = [] 
        cumUncertaintyIntegral = 0
        lastLogTime = 0
        lastUncertainty = 0
        hasLastSample = false
        policyMap
    end

    methods
        function obj = ScenarioModel()
            obj.policyMap = containers.Map('KeyType','char','ValueType','any');
            obj.policyMap('Default') = RandomWalkPolicy();
            obj.policyMap('Energy') = BatteryEfficientPolicy();
        end

        function addWall(obj, p1, p2)
            obj.walls = [obj.walls; p1(1), p1(2), p2(1), p2(2)];
        end

        function step(obj, dtSim, simTime)
            if isempty(obj.agents), return; end

            for k = 1:numel(obj.agents)
                a = obj.agents(k);
                numSubSteps = 4;
                subDt = dtSim / numSubSteps;
                
                for s = 1:numSubSteps
                    nextPos = a.state.pos + a.state.vel * subDt;
                    [hit, hitPoint] = obj.checkWallCollision(a.state.pos, nextPos);
                    
                    if hit
                        a.state.wallDetected = true;
                        a.state.lastWallPoint = hitPoint;
                        
                     
                        dirBack = (a.state.pos - hitPoint);
                        if norm(dirBack) > 1e-5
                            a.state.pos = hitPoint + (dirBack / norm(dirBack)) * 0.08;
                        else
                            a.state.pos = a.state.pos; 
                        end
                        
                    
                        a.state.vel = a.state.vel * 0.1;
                        break; 
                    else
                        a.state.wallDetected = false;
                        a.state.pos = nextPos;
                    end
                end

                if isprop(a, 'dwellRemaining') && a.dwellRemaining > 0
                    a.dwellRemaining = max(0, a.dwellRemaining - dtSim);
                    continue;
                end

                if isempty(a.path)
                    pol = obj.getPolicyForAgent(a);
                    adj = obj.buildAdjacency();
                    cmd = pol.plan(a, obj, adj, a.current_target_idx, simTime);
                    if ~isempty(cmd) && strcmp(cmd.kind, "move")
                        edge = obj.findEdge(a.current_target_idx, cmd.targetIdx);
                        if ~isempty(edge)
                            a.path = edge.curvePoints;
                            if edge.targets(1).index ~= a.current_target_idx
                                a.path = flipud(a.path);
                            end
                            a.pathIndex = 1;
                            a.current_target_idx = cmd.targetIdx;
                        end
                    end
                end
                a.update(dtSim);
            end
        end

        function [hit, point] = checkWallCollision(obj, p1, p2)
            hit = false; point = [NaN, NaN];
            moveVec = p2 - p1;
            if norm(moveVec) < 1e-6, return; end
            
            p2_ext = p2 + (moveVec / norm(moveVec)) * 0.1;

            for i = 1:size(obj.walls, 1)
                w = obj.walls(i, :);
                p3 = [w(1), w(2)]; p4 = [w(3), w(4)];
                den = (p4(2)-p3(2))*(p2_ext(1)-p1(1)) - (p4(1)-p3(1))*(p2_ext(2)-p1(2));
                if abs(den) < 1e-10, continue; end 
                ua = ((p4(1)-p3(1))*(p1(2)-p3(2)) - (p4(2)-p3(2))*(p1(1)-p3(1))) / den;
                ub = ((p2_ext(1)-p1(1))*(p1(2)-p3(2)) - (p2_ext(2)-p1(2))*(p1(1)-p3(1))) / den;
                if (ua >= 0 && ua <= 1) && (ub >= 0 && ub <= 1)
                    hit = true;
                    point = p1 + ua * (p2_ext - p1);
                    return;
                end
            end
        end

        function [uNow, JNow] = updateTargetsAndLogObjective(obj, simTime, dtSim)
            uNow = 0;
            detectionRadius = 1.2; 
            for t = 1:numel(obj.targets)
                nearby = [];
                for a_idx = 1:numel(obj.agents)
                    a = obj.agents(a_idx);
                    distToTarget = norm(a.state.pos - obj.targets(t).position);
                    if distToTarget < detectionRadius
                        if isempty(nearby), nearby = a; else, nearby(end+1) = a; end
                    end
                end
                obj.targets(t).updateResidingAgents(nearby, simTime);
                obj.targets(t).updateUncertainty(dtSim);
                uNow = uNow + obj.targets(t).R;
            end
            if ~obj.hasLastSample
                obj.lastLogTime = simTime; obj.lastUncertainty = uNow; obj.hasLastSample = true;
            else
                dt = simTime - obj.lastLogTime;
                if dt > 0
                    obj.cumUncertaintyIntegral = obj.cumUncertaintyIntegral + 0.5 * (obj.lastUncertainty + uNow) * dt;
                    obj.lastLogTime = simTime; obj.lastUncertainty = uNow;
                end
            end
            JNow = obj.cumUncertaintyIntegral / max(eps, simTime);
        end

        function s = exportLayout(obj)
            s.targets = reshape([obj.targets.position], 2, []).';
            s.edges = [];
            for k = 1:numel(obj.edges)
                ids = [obj.edges(k).targets(1).index, obj.edges(k).targets(2).index];
                s.edges = [s.edges; ids];
            end
            s.walls = obj.walls;
        end

        function importLayout(obj, s)
            obj.clearAll();
            for k = 1:size(s.targets, 1)
                obj.addTarget(s.targets(k,:));
            end
            for k = 1:size(s.edges, 1)
                obj.addEdgeByTargets(double(s.edges(k,1)), double(s.edges(k,2)));
            end
            if isfield(s, 'walls'), obj.walls = s.walls; end
        end

        function t = addTarget(obj, pos)
            t = Target(numel(obj.targets) + 1, pos);
            obj.targets(end+1) = t;
        end

        function [e, ok, msg] = addEdgeByTargets(obj, t1Idx, t2Idx)
            e = Edge.empty; ok = false; msg = "";
            if double(t1Idx) == double(t2Idx), msg = "Cannot connect to self."; return; end
            idx = numel(obj.edges) + 1;
            e = Edge(idx, [obj.targets(t1Idx), obj.targets(t2Idx)]);
            obj.edges(end+1) = e; ok = true;
        end

        function [a, ok, msg] = addAgentOnTarget(obj, clickPos, speed, tol, type)
            a = []; ok = false; msg = "";
            [tIdx, dist] = obj.findNearestTarget(clickPos);
            if isempty(tIdx) || dist > tol, msg = "Click near target"; return; end
            if nargin > 4 && strcmpi(type, "Energy")
                a = EnergyAgent(numel(obj.agents)+1, obj.targets(tIdx).position, speed);
            else
                a = DefaultAgent(numel(obj.agents)+1, obj.targets(tIdx).position, speed);
            end
            a.current_target_idx = tIdx;
            a.initialTargetIdx = tIdx;
            a.initialPosition = a.state.pos;
            if isempty(obj.agents), obj.agents = a; else, obj.agents(end+1) = a; end
            ok = true;
        end

        function clearAll(obj)
            obj.agents = []; obj.targets = Target.empty; obj.edges = Edge.empty;
            obj.walls = []; obj.cumUncertaintyIntegral = 0; obj.hasLastSample = false;
        end

        function resetSimulationState(obj)
            obj.cumUncertaintyIntegral = 0; obj.hasLastSample = false;
            for k = 1:numel(obj.agents), obj.agents(k).resetToInitial(); end
            for t = 1:numel(obj.targets), obj.targets(t).reset(); end
        end

        function [idx, dist] = findNearestTarget(obj, pos)
            idx = []; dist = inf;
            if isempty(obj.targets), return; end
            P = reshape([obj.targets.position], 2, []).';
            d = hypot(P(:,1)-pos(1), P(:,2)-pos(2));
            [dist, idx] = min(d);
        end

        function adj = buildAdjacency(obj)
            n = numel(obj.targets); adj = false(n,n);
            for k = 1:numel(obj.edges)
                e = obj.edges(k); i = e.targets(1).index; j = e.targets(2).index;
                if i>=1 && i<=n && j>=1 && j<=n, adj(i,j)=true; adj(j,i)=true; end
            end
        end

        function e = findEdge(obj, t1, t2)
            e = [];
            for k = 1:numel(obj.edges)
                ids = [obj.edges(k).targets.index];
                if all(ismember([t1, t2], ids)), e = obj.edges(k); return; end
            end
        end

        function pol = getPolicyForAgent(obj, a)
            if isprop(a, 'type') && obj.policyMap.isKey(a.type)
                pol = obj.policyMap(a.type);
            else
                pol = obj.policyMap('Default');
            end
        end
    end
end