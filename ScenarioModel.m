classdef ScenarioModel < handle
    properties
        agents  = Agent.empty
        targets = Target.empty
        edges   = Edge.empty
    end

    methods
        function clearAll(obj)
            obj.agents  = Agent.empty;
            obj.targets = Target.empty;
            obj.edges   = Edge.empty;
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
            if isempty(obj.targets)
                return;
            end
            P = reshape([obj.targets.position], 2, []).';
            d = hypot(P(:,1)-pos(1), P(:,2)-pos(2));
            [dist, idx] = min(d);
        end
    end

    methods
    function stepRandomWalk(obj, dtSim)
        % Agents do a random walk along edges between targets.
        % dtSim is simulation seconds for this tick.

        if isempty(obj.agents) || isempty(obj.targets) || isempty(obj.edges)
            return;
        end

        A = obj.buildAdjacency();

        for k = 1:numel(obj.agents)
            a = obj.agents(k);

            % If currently moving, advance toward nextTarget
            if a.movementActive && ~isempty(a.nextTarget)
                obj.advanceAgentToward(a, a.nextTarget, dtSim);
                continue;
            end

            % If dwelling, count down
            if a.dwellTime > 0
                a.dwellTime = max(0, a.dwellTime - dtSim);
                continue;
            end

            % Determine current target index
            curIdx = a.current_target_idx;
            if isempty(curIdx) || curIdx < 1 || curIdx > numel(obj.targets)
                % fallback: snap to nearest target if close enough
                [curIdx, dist] = obj.findNearestTarget(a.position);
                if isempty(curIdx) || dist > 0.5
                    continue;
                end
            end

            % Choose random neighbor
            nbrs = find(A(curIdx, :));
            if isempty(nbrs)
                continue;
            end
            nextIdx = nbrs(randi(numel(nbrs)));

            % Start moving toward that target
            a.nextTarget = obj.targets(nextIdx).position;
            a.movementActive = true;

            % IMPORTANT: set destination index so when it arrives it "knows" where it is
            a.current_target_idx = nextIdx;
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
        % Move agent toward destPos by speed*dtSim.
        delta = destPos - a.position;
        dist = norm(delta);

        if dist < 1e-9
            % Arrived
            a.position = destPos;
            a.movementActive = false;
            a.nextTarget = [];
            a.dwellTime = 0.25 + 1.0*rand(); % random dwell (tweak as desired)
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
