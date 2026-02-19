classdef Agent < handle
    properties
        index          % Unique identifier
        position       % [x,y] coordinates
        orientation    % Angle in radians (0 points to right)
        speed          % Units per second
        color          % Display color
        size           % Triangle side length
        graphicHandle  % Patch graphic handle
        textHandle     % Text label handle
        ax             % Axis handle for drawing
        current_target_idx % Current target index
        dwellTime = 0;       % Current remaining dwell time in seconds
        movementActive = false;    % Is the agent currently moving?
        xSteps = [];               % Path X
        ySteps = [];               % Path Y
        stepIndex = 1;

        % property to store the planned next target (position)
        nextTarget = [];

        % Properties for neighborhood optimization
        cluster_J
        cluster_H_opt
        cluster_optimized = false

        % Initial state (for reset)
        initialPosition
        initialOrientation
        initialTargetIdx
    end

    methods
        function obj = Agent(index, position, speed)
            % Constructor
            obj.index = index;
            obj.position = position;
            obj.orientation = 0;
            obj.speed = speed;
            obj.color = [0.8, 0.2, 0.2];
            obj.size = 8;
            obj.graphicHandle = [];
            obj.textHandle = [];
            obj.current_target_idx = [];

            % Initial state
            obj.initialPosition = position;
            obj.initialOrientation = 0;
            obj.initialTargetIdx = [];

            % Initialize optimization properties
            obj.cluster_J = Inf;
            obj.cluster_H_opt = 0;
            obj.cluster_optimized = false;

            obj.nextTarget = [];
        end

        function resetToInitial(obj)
            % Reset agent back to original placement
            obj.position = obj.initialPosition;
            obj.orientation = obj.initialOrientation;
            obj.current_target_idx = obj.initialTargetIdx;

            % Clear movement/dwell state
            obj.dwellTime = 0;
            obj.movementActive = false;
            obj.xSteps = [];
            obj.ySteps = [];
            obj.stepIndex = 1;
            obj.nextTarget = [];
        end

        function draw(obj, ax)
            obj.ax = ax;

            if ~isempty(obj.graphicHandle) && isvalid(obj.graphicHandle)
                delete(obj.graphicHandle);
            end
            if ~isempty(obj.textHandle) && isvalid(obj.textHandle)
                delete(obj.textHandle);
            end

            [x, y] = obj.calculateVertices();

            obj.graphicHandle = patch(ax, x, y, obj.color, ...
                'EdgeColor', 'k', ...
                'LineWidth', 1.5, ...
                'FaceAlpha', 0.8);

            obj.textHandle = text(ax, obj.position(1), obj.position(2), ...
                num2str(obj.index), ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', ...
                'FontWeight', 'bold', ...
                'Color', 'w', ...
                'FontSize', 8);
        end

        function [x, y] = calculateVertices(obj)
            height = obj.size * sqrt(3)/2;

            x_base = [obj.size/2, -obj.size/2, -obj.size/2, obj.size/2];
            y_base = [0, height/2, -height/2, 0];

            x_rot = x_base * cos(obj.orientation) - y_base * sin(obj.orientation);
            y_rot = x_base * sin(obj.orientation) + y_base * cos(obj.orientation);

            x = x_rot + obj.position(1);
            y = y_rot + obj.position(2);
        end

        function updatePosition(obj)
            [x, y] = obj.calculateVertices();
            if ~isempty(obj.graphicHandle) && isvalid(obj.graphicHandle)
                set(obj.graphicHandle, 'XData', x, 'YData', y);
            end
            if ~isempty(obj.textHandle) && isvalid(obj.textHandle)
                set(obj.textHandle, 'Position', [obj.position(1), obj.position(2), 0]);
            end
        end

        function moveTo(obj, targetPos)
            delta = targetPos - obj.position;
            obj.orientation = atan2(delta(2), delta(1));
            obj.position = targetPos;
        end

        function [targetPos, current_idx] = randomChoice(obj, targets, adjMatrix)
            num_targets = length(targets);
            current_idx = -1;
            proximityThresh = 0.1;
            for i = 1:num_targets
                if norm(obj.position - targets(i).position) < proximityThresh
                    current_idx = i;
                    break;
                end
            end

            if current_idx == -1
                error("Agent is not near any known target to start the walk.");
            end

            neighbors = find(adjMatrix(current_idx, :));
            if isempty(neighbors)
                targetPos = [];
                return;
            end

            next_idx = neighbors(randi(length(neighbors)));
            targetPos = targets(next_idx).position;
            obj.current_target_idx = next_idx;
        end

        function [targetPos, current_idx, optimalH] = RHCSimple(obj, targets, adjMatrix, simTime, edges)
            num_targets = length(targets);
            current_idx = -1;

            proximityThresh = 0.1;
            for i = 1:num_targets
                if norm(obj.position - targets(i).position) < proximityThresh
                    current_idx = i;
                    break;
                end
            end

            if current_idx == -1
                error('Agent is not near any known target to start the walk.');
            end

            neighbors = find(adjMatrix(current_idx, :));
            if isempty(neighbors)
                targetPos = [];
                optimalH = [];
                return;
            end

            minJ = inf;
            bestNeighborIdx = [];
            optimalH = [];
            bestCluster = {};

            for i = 1:length(neighbors)
                neighborIdx = neighbors(i);

                if ~isempty(targets(neighborIdx).residingAgents)
                    continue;
                end

                processedTargets = {};

                edge = obj.findEdge(current_idx, neighborIdx, edges);
                if isempty(edge) || isempty(targets(neighborIdx))
                    continue;
                end

                tempVisitedTarget = Target(targets(neighborIdx).index, targets(neighborIdx).position);
                tempVisitedTarget.initializeAsVisited(targets(neighborIdx), simTime, edge);
                processedTargets{end+1} = tempVisitedTarget;

                for j = 1:length(neighbors)
                    otherIdx = neighbors(j);
                    if otherIdx ~= neighborIdx
                        tempAvoidedTarget = Target(targets(otherIdx).index, targets(otherIdx).position);
                        tempAvoidedTarget.initializeAsAvoided(targets(otherIdx), simTime);
                        processedTargets{end+1} = tempAvoidedTarget;
                    end
                end

                if ~isempty(processedTargets)
                    [currentH, currentJ] = obj.optimizeClusterDwellTime(processedTargets);

                    if currentJ < minJ
                        minJ = currentJ;
                        bestNeighborIdx = neighborIdx;
                        bestCluster = processedTargets; %#ok<NASGU>
                        optimalH = currentH;
                    end
                end
            end

            if ~isempty(bestNeighborIdx)
                targetPos = targets(bestNeighborIdx).position;
                current_idx = bestNeighborIdx;
            else
                targetPos = [];
                optimalH = [];
            end
        end

        function [H_opt, J] = optimizeClusterDwellTime(obj, cluster)
            visited = [];
            avoided = {};

            for i = 1:length(cluster)
                target = cluster{i};
                if ~isempty(target.travelTime)
                    visited = target;
                else
                    avoided{end+1} = target; %#ok<AGROW>
                end
            end

            if isempty(visited)
                error('Cluster must contain one visited target.');
            end

            cost_fn = @(H) visited.objectiveVisited_numeric(H) + ...
                sum(cellfun(@(a) a.objectiveAvoided_numeric(H), avoided));

            H_lower = 0.1;
            H_upper = 6;
            H0 = (H_lower + H_upper) / 2;

            options = optimoptions('fmincon', ...
                'Display', 'off', ...
                'Algorithm', 'sqp', ...
                'TolFun', 1e-6, ...
                'TolX', 1e-6);

            [H_opt, J] = fmincon(cost_fn, H0, [], [], [], [], H_lower, H_upper, [], options);

            visited.objectiveVisited_numeric(H_opt);
            for j = 1:length(avoided)
                avoided{j}.objectiveAvoided_numeric(H_opt);
            end

            obj.cluster_H_opt = H_opt;
            obj.cluster_J = J;
            obj.cluster_optimized = true;
        end

        function J = getOptimalJ(obj)
            if ~obj.cluster_optimized
                error('Optimization has not been performed yet.');
            end
            J = obj.cluster_J;
        end

        function H_opt = getOptimalDwellTime(obj)
            if ~obj.cluster_optimized
                error('Optimization has not been performed yet.');
            end
            H_opt = obj.cluster_H_opt;
        end
    end

    methods (Access = private)
        function edge = findEdge(obj, sourceIdx, destIdx, edges)
            edge = [];
            if isempty(edges)
                return;
            end
            for e = edges
                if (e.targets(1).index == sourceIdx && e.targets(2).index == destIdx) || ...
                   (e.targets(1).index == destIdx && e.targets(2).index == sourceIdx)
                    edge = e;
                    return;
                end
            end
        end
    end
end