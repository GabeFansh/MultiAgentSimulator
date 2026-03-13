classdef ScenarioModel < handle
    properties
        agents = [] 
        targets = Target.empty
        edges = Edge.empty
        cumUncertaintyIntegral = 0 
        lastLogTime = 0 
        lastUncertainty = 0 
        hasLastSample = false
        policyMap 
        motionModel
    end

    methods
        function obj = ScenarioModel()
            obj.motionModel = SecondOrderMotionModel();
            obj.policyMap = containers.Map('KeyType','char','ValueType','any');
            obj.policyMap('Default') = RandomWalkPolicy();
        end

        function s = exportLayout(obj)
            s.targets = reshape([obj.targets.position], 2, []).';
            s.edges = [];
            for k = 1:numel(obj.edges)
                ids = [obj.edges(k).targets(1).index, obj.edges(k).targets(2).index];
                s.edges = [s.edges; ids];
            end
        end

        function importLayout(obj, s)
            obj.clearAll();
            for k = 1:size(s.targets, 1)
                obj.addTarget(s.targets(k,:));
            end
            for k = 1:size(s.edges, 1)
                obj.addEdgeByTargets(double(s.edges(k,1)), double(s.edges(k,2)));
            end
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
            a.initialPosition = a.position;
            
            if isempty(obj.agents)
                obj.agents = a;
            else
                obj.agents(end+1) = a; 
            end
            ok = true;
        end

        function clearAll(obj)
            obj.agents = []; 
            obj.targets = Target.empty; 
            obj.edges = Edge.empty;
            obj.cumUncertaintyIntegral = 0; 
            obj.hasLastSample = false;
        end

        function resetSimulationState(obj)
            obj.cumUncertaintyIntegral = 0; 
            obj.hasLastSample = false;
            for k = 1:numel(obj.agents)
                obj.agents(k).resetToInitial(); 
            end
            for t = 1:numel(obj.targets)
                obj.targets(t).reset(); 
            end
        end

        function step(obj, dtSim, simTime)
            if isempty(obj.agents), return; end
            for k = 1:numel(obj.agents)
                a = obj.agents(k);
                if isprop(a, 'dwellRemaining') && a.dwellRemaining > 0
                    a.dwellRemaining = max(0, a.dwellRemaining - dtSim); 
                    continue; 
                end
                
                if ~isempty(a.path)
                    if obj.motionModel.step(a, dtSim)
                        a.path = []; 
                        a.dwellRemaining = 0.5 + rand(); 
                    end
                else
                    pol = obj.getPolicyForAgent(a);
                    cmd = pol.plan(a, obj, obj.buildAdjacency(), a.current_target_idx, simTime);
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
            end
        end

        function [uNow, JNow] = updateTargetsAndLogObjective(obj, simTime, dtSim)
            uNow = 0;
            for t = 1:numel(obj.targets)
                nearby = [];
                for a_idx = 1:numel(obj.agents)
                    a = obj.agents(a_idx);
                    if norm(a.position - obj.targets(t).position) < 0.6
                        if isempty(nearby)
                            nearby = a;
                        else
                            nearby(end+1) = a;
                        end
                    end
                end
                obj.targets(t).updateResidingAgents(nearby, simTime);
                obj.targets(t).updateUncertainty(dtSim);
                uNow = uNow + obj.targets(t).R;
            end
            
            if ~obj.hasLastSample
                obj.lastLogTime = simTime; 
                obj.lastUncertainty = uNow; 
                obj.hasLastSample = true;
            else
                dt = simTime - obj.lastLogTime;
                if dt > 0
                    obj.cumUncertaintyIntegral = obj.cumUncertaintyIntegral + 0.5 * (obj.lastUncertainty + uNow) * dt;
                    obj.lastLogTime = simTime; 
                    obj.lastUncertainty = uNow;
                end
            end
            JNow = obj.cumUncertaintyIntegral / max(eps, simTime);
        end

        function [idx, dist] = findNearestTarget(obj, pos)
            idx = []; dist = inf; 
            if isempty(obj.targets), return; end
            P = reshape([obj.targets.position], 2, []).';
            d = hypot(P(:,1)-pos(1), P(:,2)-pos(2)); 
            [dist, idx] = min(d);
        end

        function adj = buildAdjacency(obj)
            n = numel(obj.targets); 
            adj = false(n,n);
            for k = 1:numel(obj.edges)
                e = obj.edges(k);
                i = e.targets(1).index; 
                j = e.targets(2).index;
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