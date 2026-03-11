classdef SecondOrderMotionModel < handle
    properties
        kp = 8.0           
        kd = 12.0          
        lookAheadDist = 5.0 
        arrivePosTol = 0.5 
    end

    methods
        function arrived = step(obj, agent, dt)
            arrived = false;
            
            if isprop(agent, 'battery_percentage')
                if agent.battery_percentage <= 0
                    agent.velocity = [0 0];
                    agent.acceleration = [0 0];
                    if isprop(agent, 'mode'), agent.mode = "power_outage"; end
                    if ismethod(agent, 'calculate_energy'), agent.calculate_energy(dt); end
                    return;
                end
            end

            if isempty(agent.path)
                if isprop(agent, 'mode'), agent.mode = "dwelling"; end
                if ismethod(agent, 'calculate_energy'), agent.calculate_energy(dt); end
                return;
            end

            if isprop(agent, 'mode'), agent.mode = "traveling"; end
            targetPos = agent.path(agent.pathIndex, :);
            dist = norm(targetPos - agent.position);

            while dist < obj.lookAheadDist && agent.pathIndex < size(agent.path, 1)
                agent.pathIndex = agent.pathIndex + 1;
                targetPos = agent.path(agent.pathIndex, :);
                dist = norm(targetPos - agent.position);
            end

            if agent.pathIndex == size(agent.path, 1) && dist < obj.arrivePosTol
                agent.velocity = [0 0];
                agent.acceleration = [0 0];
                arrived = true;
                if isprop(agent, 'mode'), agent.mode = "dwelling"; end
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
                
                if norm(agent.velocity) > 1e-3
                    agent.orientation = atan2(agent.velocity(2), agent.velocity(1));
                end
            end
            
            if ismethod(agent, 'calculate_energy')
                agent.calculate_energy(dt);
            end
        end
    end
end