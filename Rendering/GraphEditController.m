classdef GraphEditController < handle
    properties
        model
        renderer

        mode = "idle"      % "idle" | "addTarget" | "addAgent" | "addEdge" | "addWall"
        edgePick = []      
        wallPoints = []    % Stores the first point of a wall during placement

        clickTol = 3.0
        statusCallback 

        gridStep = 5

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
            obj.wallPoints = []; % Clear partial wall placement
            obj.renderer.resetEdgePreview();
            obj.say("Mode: " + obj.mode);
        end

        function importBackground(obj)
            obj.renderer.loadBackgroundImage();
            obj.say("Background image loaded. You can now trace targets over the map.");
        end

        function clearAll(obj)
            obj.renderer.clearAxes();  
            obj.model.clearAll();
            obj.renderer.renderAll(obj.model);
            obj.setMode("idle");
        end

        function onCanvasClick(obj, pos, agentSpeed)
            % Snap to grid for targets and walls to keep layout clean
            snappedPos = obj.snapToGrid(pos, obj.gridStep);
            snappedPos = obj.clampToBounds(snappedPos);

            switch obj.mode
                case "addTarget"
                    obj.model.addTarget(snappedPos);
                    obj.renderer.renderAll(obj.model);

                case "addAgent"
                    selectedType = "Energy"; 
                    [~, ok, msg] = obj.model.addAgentOnTarget(pos, agentSpeed, obj.clickTol, selectedType);
                    if ~ok && msg ~= ""
                        obj.say(msg);
                        return;
                    end
                    obj.renderer.renderAll(obj.model);

                case "addEdge"
                    obj.handleEdgePick(pos);

                case "addWall"
                    if isempty(obj.wallPoints)
                        % First click: Start of the wall
                        obj.wallPoints = snappedPos;
                        obj.say("Start point set. Click again for end point.");
                        obj.renderer.updateEdgePreview(obj.wallPoints, snappedPos);
                    else
                        % Second click: End of the wall
                        obj.model.addWall(obj.wallPoints, snappedPos);
                        obj.wallPoints = [];
                        obj.renderer.resetEdgePreview();
                        obj.renderer.renderAll(obj.model);
                        obj.say("Wall added.");
                    end
            end
        end

        function onCanvasMove(obj, pos)
            % Reuse edge preview for both Edges and Walls
            if obj.mode == "addEdge" && ~isempty(obj.edgePick)
                p1 = obj.model.targets(obj.edgePick(1)).position;
                obj.renderer.updateEdgePreview(p1, pos);
            
            elseif obj.mode == "addWall" && ~isempty(obj.wallPoints)
                % Show preview line from first wall point to mouse cursor
                snappedPos = obj.snapToGrid(pos, obj.gridStep);
                snappedPos = obj.clampToBounds(snappedPos);
                obj.renderer.updateEdgePreview(obj.wallPoints, snappedPos);
            end
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
                obj.renderer.updateEdgePreview(p1, pos);
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