classdef GraphEditController < handle
    properties
        model
        renderer

        mode = "idle"      % "idle" | "addTarget" | "addAgent" | "addEdge"
        edgePick = []      % picked target indices

        clickTol = 3.0
        statusCallback 

        % Grid snap settings
        gridStep = 5

        % Bounds 
        xMin = 0
        xMax = 100
        yMin = 0
        yMax = 100
    end

    methods
        function obj = GraphEditController(model, renderer, statusCallback)
            obj.model = model;
            obj.renderer = renderer;
            obj.statusCallback = statusCallback;
        end

        function setMode(obj, m)
            obj.mode = string(m);
            obj.edgePick = [];
            obj.renderer.resetEdgePreview();
            obj.say("Mode: " + obj.mode);
        end

        function clearAll(obj)
            obj.renderer.clearAxes();  % delete bars/rectangles first
            obj.model.clearAll();
            obj.renderer.renderAll(obj.model);
            obj.setMode("idle");
        end

        function onCanvasClick(obj, pos, agentSpeed)
            switch obj.mode
                case "addTarget"
                    pos2 = obj.snapToGrid(pos, obj.gridStep);
                    pos2 = obj.clampToBounds(pos2);
                    obj.model.addTarget(pos2);
                    obj.renderer.renderAll(obj.model);

                case "addAgent"
                    [~, ok, msg] = obj.model.addAgentOnTarget(pos, agentSpeed, obj.clickTol);
                    if ~ok && msg ~= ""
                        obj.say(msg);
                        return;
                    end
                    obj.renderer.renderAll(obj.model);

                case "addEdge"
                    obj.handleEdgePick(pos);

                otherwise
                    % idle
            end
        end

        function onCanvasMove(obj, pos)
            if obj.mode ~= "addEdge"
                return;
            end
            if numel(obj.edgePick) ~= 1
                return;
            end

            pos2 = obj.snapToGrid(pos, obj.gridStep);
            pos2 = obj.clampToBounds(pos2);

            p1 = obj.model.targets(obj.edgePick(1)).position;
            obj.renderer.updateEdgePreview(p1, pos2);
        end
    end

    methods (Access=private)
        function handleEdgePick(obj, pos)
            if numel(obj.model.targets) < 2
                obj.say("Add at least 2 targets first.");
                return;
            end

            [tIdx, dist] = obj.model.findNearestTarget(pos);
            if isempty(tIdx) || dist > obj.clickTol
                return;
            end
            if any(obj.edgePick == tIdx)
                return;
            end

            obj.edgePick(end+1) = tIdx;

            if isscalar(obj.edgePick)
                obj.say(sprintf("Picked T%d. Pick second target...", tIdx));
                p1 = obj.model.targets(tIdx).position;

                pos2 = obj.snapToGrid(pos, obj.gridStep);
                pos2 = obj.clampToBounds(pos2);

                obj.renderer.updateEdgePreview(p1, pos2);
                return;
            end

            i = obj.edgePick(1);
            j = obj.edgePick(2);

            [~, ok, msg] = obj.model.addEdgeByTargets(i, j);
            if ~ok
                obj.say(msg);
            else
                obj.say(sprintf("Created edge T%d—T%d", i, j));
            end

            obj.edgePick = [];
            obj.renderer.resetEdgePreview();
            obj.renderer.renderAll(obj.model);
        end

        function say(obj, msg)
            if ~isempty(obj.statusCallback)
                obj.statusCallback(char(msg));
            end
        end

        function p = snapToGrid(~, p, step)
            p = step * round(p ./ step);
        end

        function p = clampToBounds(obj, p)
            p(1) = min(max(p(1), obj.xMin), obj.xMax);
            p(2) = min(max(p(2), obj.yMin), obj.yMax);
        end
    end
end