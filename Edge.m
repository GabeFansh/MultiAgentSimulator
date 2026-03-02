classdef Edge < handle
    properties
        index
        targets % [target1, target2]
        curvePoints % Nx2 matrix for the actual curve
        lineHandle
    end
    
    methods
        function obj = Edge(index, targetPair)
            obj.index = index;
            obj.targets = targetPair;
            obj.generateCurve();
        end
        
        function generateCurve(obj)
            p1 = obj.targets(1).position;
            p2 = obj.targets(2).position;
            
            mid = (p1 + p2) / 2;
            perp = [-(p2(2)-p1(2)), (p2(1)-p1(1))];
            controlPoint = mid + 0.2 * perp; 
            
            t = linspace(0, 1, 20)';
            % Quadratic Bezier
            obj.curvePoints = (1-t).^2 * p1 + 2*(1-t).*t * controlPoint + t.^2 * p2;
        end
        
        function draw(obj, ax)
            obj.lineHandle = plot(ax, obj.curvePoints(:,1), obj.curvePoints(:,2), ...
                'k-', 'LineWidth', 1, 'Color', [0.5 0.5 0.5]);
        end
    end
end