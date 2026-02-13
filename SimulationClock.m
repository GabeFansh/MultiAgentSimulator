classdef SimulationClock < handle
    properties
        currentTime double = 0
        endTime double = 60
        dt double = 0.05           % base simulation step (seconds)
        timeScale double = 1.0     % multiplier
    end

    methods
        function obj = SimulationClock(endTime, dt)
            if nargin >= 1 && ~isempty(endTime), obj.endTime = endTime; end
            if nargin >= 2 && ~isempty(dt), obj.dt = dt; end
        end

        function reset(obj)
            obj.currentTime = 0;
        end

        function dtSim = tick(obj)
            dtSim = obj.dt * obj.timeScale;

            remaining = obj.endTime - obj.currentTime;
            if remaining <= 0
                dtSim = 0;
                obj.currentTime = obj.endTime;
                return;
            end

            if dtSim > remaining
                dtSim = remaining;
            end

            obj.currentTime = obj.currentTime + dtSim;
        end


        function tf = isFinished(obj)
            tf = obj.currentTime >= obj.endTime;
        end
    end
end
