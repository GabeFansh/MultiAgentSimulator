classdef DefaultAgent < handle
    properties
        index
        position double = [0 0]
        velocity double = [0 0]
        acceleration double = [0 0]      
        orientation double = 0
        
        % Hardcoded physical limits
        maxSpeed double = 5             
        maxAccel double = 15             

        % Pathing properties
        path = []                        
        pathIndex = 1                    
        
        current_target_idx = []
        dwellRemaining double = 0
        nextDwell = []
        type string = "Default"

        color = [0.8 0.2 0.2]; size = 8;
        graphicHandle; textHandle; ax;

        initialPosition; initialVelocity; initialOrientation;
        initialTargetIdx;               
    end

    methods
        function obj = DefaultAgent(index, position, maxSpeed)
            obj.index = index;
            obj.position = position;
            obj.maxSpeed = maxSpeed;
            obj.initialPosition = position;
            obj.initialVelocity = [0 0];
        end

        function resetToInitial(obj)
            obj.position = obj.initialPosition;
            obj.velocity = [0 0];
            obj.acceleration = [0 0];
            obj.orientation = 0;
            obj.path = [];
            obj.pathIndex = 1;
            obj.dwellRemaining = 0;
            obj.current_target_idx = obj.initialTargetIdx; %
        end

        function draw(obj, ax)
            obj.ax = ax;
            if ~isempty(obj.graphicHandle) && isvalid(obj.graphicHandle), delete(obj.graphicHandle); end
            [x, y] = obj.calculateVertices();
            obj.graphicHandle = patch(ax, x, y, obj.color, 'EdgeColor', 'k', 'FaceAlpha', 0.8);
            obj.textHandle = text(ax, obj.position(1), obj.position(2), num2str(obj.index), ...
                'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'Color', 'w', 'FontSize', 8);
        end

        function updatePosition(obj)
            if isempty(obj.graphicHandle) || ~isgraphics(obj.graphicHandle), return; end
            [x, y] = obj.calculateVertices();
            set(obj.graphicHandle, 'XData', x, 'YData', y);
            set(obj.textHandle, 'Position', [obj.position(1), obj.position(2), 0]);
        end
    end

    methods (Access=private)
        function [x, y] = calculateVertices(obj)
            h = obj.size * sqrt(3)/2;
            xb = [obj.size/2, -obj.size/2, -obj.size/2, obj.size/2];
            yb = [0, h/2, -h/2, 0];
            x = xb*cos(obj.orientation) - yb*sin(obj.orientation) + obj.position(1);
            y = xb*sin(obj.orientation) + yb*cos(obj.orientation) + obj.position(2);
        end
    end
end