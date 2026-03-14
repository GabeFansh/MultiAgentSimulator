classdef EnergyAgent < handle
    properties
        index
        position double = [0 0]
        velocity double = [0 0]
        acceleration double = [0 0]
        orientation double = 0
        
        % Physical Limits
        maxSpeed double = 5             
        maxAccel double = 15             

        % Pathing
        path = []                        
        pathIndex = 1
        
        current_target_idx = []
        dwellRemaining double = 0
        mode string = "idle" 
        
        % ===== ENERGY PROPERTIES =====
        e_total = 0;
        soc = 1.0;                      
        battery_percentage = 100;
        e_total_history = [0];
        
        % Visualization
        color = [0.8 0.2 0.2]; size = 8;
        graphicHandle; textHandle; ax;

        % Initial state for resets
        initialPosition; initialTargetIdx;
    end

    properties (Constant)
        % ===== POWER COEFFICIENTS =====
        MASS = 10.0;              
        ROLLING_FRICTION = 0.02;  
        GRAVITY = 9.81;           
        P0_BASE_MOTION = 5.82;    
        ALPHA_VEL = 0.02 * 10 * 9.81; 
        GAMMA_ACC = 0.5;          
        
        % CPU and Component Power
        CPU_MOVE = 5.5;           
        CPU_IDLE = 4.0;           
        COMP_ACTIVE = 11.7;       
        COMP_STANDBY = 11.0;      
        
        % Battery Specs
        BATTERY_E_Wh = 26.0;      
        BAT_MON_V = 14.4;         
        ETA_CONV = 0.90;          
    end

    methods
        function obj = EnergyAgent(index, position, maxSpeed)
            obj.index = index;
            obj.position = position;
            obj.maxSpeed = maxSpeed;
            obj.initialPosition = position;
        end

        function resetToInitial(obj)
            obj.position = obj.initialPosition;
            obj.velocity = [0 0];
            obj.acceleration = [0 0];
            obj.e_total = 0;
            obj.soc = 1.0;
            obj.battery_percentage = 100;
            obj.e_total_history = 0;
            obj.path = [];
            obj.pathIndex = 1;
            obj.dwellRemaining = 0;
            obj.mode = "idle";
            obj.current_target_idx = obj.initialTargetIdx;
        end

        % ===== ENERGY CALCULATION =====
        function calculate_energy(obj, dt)
            % Motion Power: P_move = P0 + alpha*v + gamma*u^2
            v_norm = norm(obj.velocity);
            a_norm = norm(obj.acceleration);
            p_mot = obj.P0_BASE_MOTION + (obj.ALPHA_VEL * v_norm) + (obj.GAMMA_ACC * a_norm^2);

            % Power draw based on current mode
            if obj.mode == "traveling"
                p_cpu = obj.CPU_MOVE;
                p_comp = obj.COMP_ACTIVE;
            else
                p_cpu = obj.CPU_IDLE;
                p_comp = obj.COMP_STANDBY;
            end

            % Apply efficiency and update SOC
            p_total = (p_cpu + p_comp + p_mot) / obj.ETA_CONV;
            energy_step = p_total * dt;
            obj.e_total = obj.e_total + energy_step;
            obj.e_total_history(end+1) = obj.e_total;

            % Coulomb Counting
            Q_joules = obj.BATTERY_E_Wh * 3600;
            obj.soc = obj.soc - (energy_step / Q_joules);
            obj.battery_percentage = max(0, obj.soc * 100);
        end

        function draw(obj, ax)
            obj.ax = ax;
            if ~isempty(obj.graphicHandle) && isvalid(obj.graphicHandle), delete(obj.graphicHandle); end
            [x, y] = obj.calculateVertices();
            obj.graphicHandle = patch(ax, x, y, obj.color, 'EdgeColor', 'k', 'FaceAlpha', 0.8);
            
            % Update text to show battery if applicable
            labelStr = num2str(obj.index);
            if isprop(obj, 'battery_percentage')
                labelStr = sprintf('%d\n%.0f%%', obj.index, obj.battery_percentage);
            end
            
            obj.textHandle = text(ax, obj.position(1), obj.position(2), labelStr, ...
                'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'Color', 'w', 'FontSize', 7);
        end

        function updatePosition(obj)
            if isempty(obj.graphicHandle) || ~isgraphics(obj.graphicHandle), return; end
            [x, y] = obj.calculateVertices();
            set(obj.graphicHandle, 'XData', x, 'YData', y);
            
            labelStr = num2str(obj.index);
            if isprop(obj, 'battery_percentage')
                labelStr = sprintf('%d\n%.0f%%', obj.index, obj.battery_percentage);
            end
            
            set(obj.textHandle, 'Position', [obj.position(1), obj.position(2), 0], 'String', labelStr);
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