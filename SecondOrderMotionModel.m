classdef SecondOrderMotionModel < handle
    properties
        
        kp = 5.0           
        kd = 10.0          
        
        
        lookAheadDist = 8.0 
        
        arrivePosTol = 0.8 
    end

    methods
        function arrived = step(obj, agent, dt)
            arrived = false;
            
            if isprop(agent, 'battery_percentage') && agent.battery_percentage <= 0
                agent.velocity = agent.velocity * 0.9; 
                agent.acceleration = [0 0];
                if isprop(agent, 'mode'), agent.mode = "power_outage"; end
                if ismethod(agent, 'calculate_energy'), agent.calculate_energy(dt); end
                return;
            end

            if isempty(agent.path)
                agent.velocity = agent.velocity * 0.8;
                if isprop(agent, 'mode'), agent.mode = "dwelling"; end
                if ismethod(agent, 'calculate_energy'), agent.calculate_energy(dt); end
                return;
            end

            if isprop(agent, 'mode'), agent.mode = "traveling"; end
            
            targetPos = agent.path(agent.pathIndex, :);
            distToCurrentPoint = norm(targetPos - agent.position);

            while distToCurrentPoint < obj.lookAheadDist && agent.pathIndex < size(agent.path, 1)
                agent.pathIndex = agent.pathIndex + 1;
                targetPos = agent.path(agent.pathIndex, :);
                distToCurrentPoint = norm(targetPos - agent.position);
            end

            distToFinalGoal = norm(agent.path(end, :) - agent.position);
            
            if agent.pathIndex == size(agent.path, 1) && distToFinalGoal < obj.arrivePosTol
                
                agent.velocity = agent.velocity * 0.5; 
                if norm(agent.velocity) < 0.1
                    agent.velocity = [0 0];
                    agent.acceleration = [0 0];
                    arrived = true;
                    if isprop(agent, 'mode'), agent.mode = "dwelling"; end
                end
            else
                aCmd = obj.kp * (targetPos - agent.position) - obj.kd * agent.velocity;
                
                if norm(aCmd) > agent.maxAccel
                    aCmd = (aCmd / norm(aCmd)) * agent.maxAccel;
                end
                
                agent.acceleration = aCmd;
                agent.velocity = agent.velocity + agent.acceleration * dt;
                
                if norm(agent.velocity) > agent.maxSpeed
                    agent.velocity = (agent.velocity / norm(agent.velocity)) * agent.maxSpeed;
                end
                
                agent.position = agent.position + agent.velocity * dt;
                
                if norm(agent.velocity) > 0.1
                    targetHeading = atan2(agent.velocity(2), agent.velocity(1));
                    agent.orientation = targetHeading;
                end
            end
            
            if ismethod(agent, 'calculate_energy')
                agent.calculate_energy(dt);
            end
        end
    end
end