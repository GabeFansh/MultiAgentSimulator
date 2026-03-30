classdef PathFollowerController < handle
    properties
        kp = 5.0            
        kd = 10.0           
        lookAheadDist = 8.0 
        arrivePosTol = 0.8  
    end

    methods
        function [arrived, aCmd, pathIndex] = computeControl(obj, state, path, pathIndex, ~)
            arrived = false;
            aCmd = [0 0]; 

            if isempty(path)
                aCmd = -obj.kd * state.vel;
                return;
            end

            targetPos = path(pathIndex, :);
            distToCurrentPoint = norm(targetPos - state.pos);

            while distToCurrentPoint < obj.lookAheadDist && pathIndex < size(path, 1)
                pathIndex = pathIndex + 1;
                targetPos = path(pathIndex, :);
                distToCurrentPoint = norm(targetPos - state.pos);
            end

            distToFinalGoal = norm(path(end, :) - state.pos);
            
            if pathIndex == size(path, 1) && distToFinalGoal < obj.arrivePosTol
                aCmd = -obj.kd * state.vel; 
                if norm(state.vel) < 0.1
                    aCmd = [0 0];
                    arrived = true;
                end
            else
                aCmd = obj.kp * (targetPos - state.pos) - obj.kd * state.vel;
                
                if norm(aCmd) > state.maxAccel
                    aCmd = (aCmd / norm(aCmd)) * state.maxAccel;
                end
            end
        end
    end
end