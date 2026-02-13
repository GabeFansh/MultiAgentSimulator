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
end
