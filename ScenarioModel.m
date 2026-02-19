classdef ScenarioModel < handle
    properties
        agents  = Agent.empty
        targets = Target.empty
        edges   = Edge.empty

        % Objective logging
        timeHistory = []
        uncertaintyHistory = []

        % NEW: incremental integral for J(t) (exact trapezoid rule)
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
            a.initialTargetIdx = tIdx;
            a.initialPosition = snapPos;
            a.initialOrientation = a.orientation;

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

            % --- Update each target's residing agents + uncertainty ---
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

            % --- Log history (optional but useful for plotting/debug) ---
            obj.timeHistory(end+1) = simTime;
            obj.uncertaintyHistory(end+1) = uNow;

            % --- Incremental trapezoid integral for J(t) ---
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
            else
                % no time advance (dt=0): do not change integral
            end

            if simTime <= 0
                JNow = 0;
            else
                JNow = obj.cumUncertaintyIntegral / simTime;
            end
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