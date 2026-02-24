classdef ScenarioModel < handle
    properties
        agents  = Agent.empty
        targets = Target.empty
        edges   = Edge.empty

        % Objective logging
        timeHistory = []
        uncertaintyHistory = []

        % incremental integral for J(t)
        cumUncertaintyIntegral double = 0
        lastLogTime double = 0
        lastUncertainty double = 0
        hasLastSample logical = false
    end

    methods
        function clearAll(obj)
            obj.agents  = Agent.empty;
            obj.targets = Target.empty;
            obj.edges   = Edge.empty;

            obj.timeHistory = [];
            obj.uncertaintyHistory = [];

            obj.cumUncertaintyIntegral = 0;
            obj.lastLogTime = 0;
            obj.lastUncertainty = 0;
            obj.hasLastSample = false;
        end

        function resetSimulationState(obj)
            % Reset objective logs
            obj.timeHistory = [];
            obj.uncertaintyHistory = [];

            obj.cumUncertaintyIntegral = 0;
            obj.lastLogTime = 0;
            obj.lastUncertainty = 0;
            obj.hasLastSample = false;

            % Reset agents to initial placement
            for k = 1:numel(obj.agents)
                if ismethod(obj.agents(k), 'resetToInitial')
                    obj.agents(k).resetToInitial();
                end
            end

            % Reset targets if they implement reset()
            for t = 1:numel(obj.targets)
                if ismethod(obj.targets(t), 'reset')
                    obj.targets(t).reset();
                end
            end
        end

        function t = addTarget(obj, pos)
            idx = numel(obj.targets) + 1;
            t = Target(idx, pos);
            obj.targets(idx) = t;
        end

        function [a, ok, msg] = addAgentOnTarget(obj, clickPos, speed, tol)
            a = Agent.empty;
            ok = false;
            msg = "";

            if isempty(obj.targets)
                msg = "Add at least 1 target before adding agents.";
                return;
            end

            [tIdx, dist] = obj.findNearestTarget(clickPos);
            if isempty(tIdx) || dist > tol
                msg = sprintf("Click on/near a target to place an agent (within %.1f units).", tol);
                return;
            end

            snapPos = obj.targets(tIdx).position;
            idx = numel(obj.agents) + 1;

            a = Agent(idx, snapPos, speed);
            a.current_target_idx = tIdx;

            % Ensure initial state is correct
            if isprop(a,'initialTargetIdx'), a.initialTargetIdx = tIdx; end
            if isprop(a,'initialPosition'), a.initialPosition = snapPos; end
            if isprop(a,'initialOrientation'), a.initialOrientation = a.orientation; end

            obj.agents(idx) = a;
            ok = true;
        end

        function [e, ok, msg] = addEdgeByTargets(obj, t1Idx, t2Idx)
            e = Edge.empty;
            ok = false;
            msg = "";

            if t1Idx == t2Idx
                msg = "Cannot connect a target to itself.";
                return;
            end

            if obj.edgeExists(t1Idx, t2Idx)
                msg = sprintf("Edge between T%d and T%d already exists.", t1Idx, t2Idx);
                return;
            end

            idx = numel(obj.edges) + 1;
            e = Edge(idx, [obj.targets(t1Idx), obj.targets(t2Idx)]);
            obj.edges(idx) = e;
            ok = true;
        end

        function tf = edgeExists(obj, i, j)
            tf = false;
            for k = 1:numel(obj.edges)
                t = obj.edges(k).targets;
                a = t(1).index; b = t(2).index;
                if (a==i && b==j) || (a==j && b==i)
                    tf = true;
                    return;
                end
            end
        end

        function [idx, dist] = findNearestTarget(obj, pos)
            idx = [];
            dist = inf;
            if isempty(obj.targets), return; end
            P = reshape([obj.targets.position], 2, []).';
            d = hypot(P(:,1)-pos(1), P(:,2)-pos(2));
            [dist, idx] = min(d);
        end

        % ===== Simulation: Random walk (continuous movement) =====
        function stepRandomWalk(obj, dtSim)
            if isempty(obj.agents) || isempty(obj.targets) || isempty(obj.edges)
                return;
            end

            A = obj.buildAdjacency();

            for k = 1:numel(obj.agents)
                a = obj.agents(k);

                if a.movementActive && ~isempty(a.nextTarget)
                    obj.advanceAgentToward(a, a.nextTarget, dtSim);
                    continue;
                end

                if a.dwellTime > 0
                    a.dwellTime = max(0, a.dwellTime - dtSim);
                    continue;
                end

                curIdx = a.current_target_idx;
                if isempty(curIdx) || curIdx < 1 || curIdx > numel(obj.targets)
                    [curIdx, dist] = obj.findNearestTarget(a.position);
                    if isempty(curIdx) || dist > 0.5
                        continue;
                    end
                end

                nbrs = find(A(curIdx, :));
                if isempty(nbrs), continue; end

                nextIdx = nbrs(randi(numel(nbrs)));

                a.nextTarget = obj.targets(nextIdx).position;
                a.movementActive = true;
                a.current_target_idx = nextIdx;
            end
        end

        % ===== Objective: accurate in fast-forward too =====
        function [uNow, JNow] = updateTargetsAndLogObjective(obj, simTime, dtSim)
            if isempty(obj.targets)
                uNow = 0;
                JNow = 0;
                return;
            end

            uNow = 0;
            for t = 1:numel(obj.targets)
                nearby = Agent.empty(0,0);
                for a = 1:numel(obj.agents)
                    if norm(obj.agents(a).position - obj.targets(t).position) < 0.1
                        nearby(end+1) = obj.agents(a); %#ok<AGROW>
                    end
                end

                obj.targets(t).updateResidingAgents(nearby, simTime);
                obj.targets(t).updateUncertainty(dtSim);

                uNow = uNow + obj.targets(t).R;
            end

            obj.timeHistory(end+1) = simTime;
            obj.uncertaintyHistory(end+1) = uNow;

            if ~obj.hasLastSample
                obj.lastLogTime = simTime;
                obj.lastUncertainty = uNow;
                obj.cumUncertaintyIntegral = 0;
                obj.hasLastSample = true;
                JNow = 0;
                return;
            end

            dt = simTime - obj.lastLogTime;
            if dt > 0
                obj.cumUncertaintyIntegral = obj.cumUncertaintyIntegral + 0.5 * (obj.lastUncertainty + uNow) * dt;
                obj.lastLogTime = simTime;
                obj.lastUncertainty = uNow;
            end

            if simTime <= 0
                JNow = 0;
            else
                JNow = obj.cumUncertaintyIntegral / simTime;
            end
        end

        % =======================
        % Layout Save / Load API
        % =======================
        function s = exportLayout(obj)
            s = struct();
            s.version = 1;
            s.createdAt = char(datetime('now'));

            % Targets
            nT = numel(obj.targets);
            s.targets = repmat(struct('index',[],'position',[],'A',[],'B',[],'R',[]), 1, nT);
            for i = 1:nT
                t = obj.targets(i);
                s.targets(i).index = t.index;
                s.targets(i).position = t.position;

                if isprop(t,'A'), s.targets(i).A = t.A; end
                if isprop(t,'B'), s.targets(i).B = t.B; end
                if isprop(t,'R'), s.targets(i).R = t.R; end
            end

            % Edges (by target indices)
            nE = numel(obj.edges);
            s.edges = repmat(struct('i',[],'j',[]), 1, nE);
            for k = 1:nE
                e = obj.edges(k);
                s.edges(k).i = e.targets(1).index;
                s.edges(k).j = e.targets(2).index;
            end

            % Agents
            nA = numel(obj.agents);
            s.agents = repmat(struct('index',[],'initialTargetIdx',[],'initialPosition',[],'speed',[]), 1, nA);
            for i = 1:nA
                a = obj.agents(i);
                s.agents(i).index = a.index;

                if isprop(a,'initialTargetIdx') && ~isempty(a.initialTargetIdx)
                    s.agents(i).initialTargetIdx = a.initialTargetIdx;
                else
                    s.agents(i).initialTargetIdx = a.current_target_idx;
                end

                if isprop(a,'initialPosition') && ~isempty(a.initialPosition)
                    s.agents(i).initialPosition = a.initialPosition;
                else
                    s.agents(i).initialPosition = a.position;
                end

                s.agents(i).speed = a.speed;
            end
        end

        function importLayout(obj, s)
            % Rebuild everything from layout struct
            obj.clearAll();

            % Targets
            for i = 1:numel(s.targets)
                tt = s.targets(i);
                t = obj.addTarget(tt.position);

                % Keep index consistent if user saved it
                t.index = tt.index;

                if isfield(tt,'A') && ~isempty(tt.A) && isprop(t,'A'), t.A = tt.A; end
                if isfield(tt,'B') && ~isempty(tt.B) && isprop(t,'B'), t.B = tt.B; end

                if isfield(tt,'R') && ~isempty(tt.R) && isprop(t,'R')
                    t.R = tt.R;                   
                end
            end

            % Edges
            for k = 1:numel(s.edges)
                obj.addEdgeByTargets(s.edges(k).i, s.edges(k).j);
            end

            % Agents
            for i = 1:numel(s.agents)
                aa = s.agents(i);
                idx = numel(obj.agents) + 1;

                pos = aa.initialPosition;
                tIdx = aa.initialTargetIdx;

                if ~isempty(tIdx) && tIdx >= 1 && tIdx <= numel(obj.targets)
                    pos = obj.targets(tIdx).position;
                end

                a = Agent(idx, pos, aa.speed);
                a.current_target_idx = tIdx;

                if isprop(a,'initialTargetIdx'), a.initialTargetIdx = tIdx; end
                if isprop(a,'initialPosition'), a.initialPosition = pos; end
                if isprop(a,'initialOrientation'), a.initialOrientation = a.orientation; end

                obj.agents(idx) = a;
            end

            % Reset objective integrator
            obj.timeHistory = [];
            obj.uncertaintyHistory = [];
            obj.cumUncertaintyIntegral = 0;
            obj.lastLogTime = 0;
            obj.lastUncertainty = 0;
            obj.hasLastSample = false;
        end
    end

    methods (Access=private)
        function A = buildAdjacency(obj)
            n = numel(obj.targets);
            A = false(n,n);
            for e = obj.edges
                i = e.targets(1).index;
                j = e.targets(2).index;
                if i>=1 && i<=n && j>=1 && j<=n
                    A(i,j) = true;
                    A(j,i) = true;
                end
            end
        end

        function advanceAgentToward(~, a, destPos, dtSim)
            delta = destPos - a.position;
            dist = norm(delta);

            if dist < 1e-9
                a.position = destPos;
                a.movementActive = false;
                a.nextTarget = [];
                a.dwellTime = 0.25 + 1.0*rand();
                return;
            end

            step = a.speed * dtSim;
            if step >= dist
                a.position = destPos;
                a.movementActive = false;
                a.nextTarget = [];
                a.dwellTime = 0.25 + 1.0*rand();
            else
                dir = delta / dist;
                a.position = a.position + dir * step;
                a.orientation = atan2(dir(2), dir(1));
            end
        end
    end
end