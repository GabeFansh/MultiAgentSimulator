classdef SimulationController < handle
    properties
        model
        renderer
        clock

        timerObj
        isRunning logical = false

        % callbacks for UI
        timeCallback    % @(t) ...
        statusCallback  % @(msg) ...
    end

    properties (Access=private)
        realPeriod = 0.03  % seconds (how often MATLAB timer fires)
        fastForwardChunkSteps = 2000
    end

    methods
        function obj = SimulationController(model, renderer, clock, timeCb, statusCb)
            obj.model = model;
            obj.renderer = renderer;
            obj.clock = clock;
            obj.timeCallback = timeCb;
            obj.statusCallback = statusCb;

            obj.timerObj = timer( ...
                'ExecutionMode','fixedSpacing', ...
                'Period', obj.realPeriod, ...
                'BusyMode','drop', ...
                'TimerFcn', @(~,~)obj.onTimerTick());
        end

        function delete(obj)
            obj.stopTimer();
            if ~isempty(obj.timerObj) && isvalid(obj.timerObj)
                delete(obj.timerObj);
            end
        end

        function play(obj)
            if obj.clock.isFinished()
                obj.clock.reset();
                obj.say("Reset time to 0.");
            end
            if obj.isRunning, return; end
            obj.isRunning = true;
            start(obj.timerObj);
            obj.say("Playing.");
        end

        function pause(obj)
            obj.stopTimer();
            obj.say("Paused.");
        end

        function runToEnd(obj)
            % Fast-forward: compute quickly, then render final state
            obj.pause();
            if obj.clock.isFinished()
                obj.say("Already at end.");
                return;
            end

            obj.say("Fast-forwarding to end...");

            % Run in chunks so UI stays responsive
            while ~obj.clock.isFinished()
                steps = obj.fastForwardChunkSteps;
                for k = 1:steps
                    if obj.clock.isFinished(), break; end
                    dtSim = obj.clock.tick();
                    obj.model.stepRandomWalk(dtSim);
                end
                obj.publishTime();
                drawnow limitrate;
            end

            % final render
            obj.renderer.renderAgents(obj.model);
            obj.publishTime();
            obj.say("Reached end.");
        end

        function setEndTime(obj, tEnd)
            obj.clock.endTime = max(0, tEnd);
            if obj.clock.currentTime > obj.clock.endTime
                obj.clock.currentTime = obj.clock.endTime;
            end
            obj.publishTime();
        end


        function setDt(obj, dt)
            obj.clock.dt = max(1e-4, dt);
        end

        function setTimeScale(obj, s)
            obj.clock.timeScale = max(0, s);
        end

        function reset(obj)
            obj.pause();
            obj.clock.reset();
            obj.publishTime();
            obj.say("Reset.");
        end
    end

    methods (Access=private)
        function onTimerTick(obj)
            if obj.clock.isFinished()
                obj.pause();
                obj.say("Reached end.");
                return;
            end

            dtSim = obj.clock.tick();
            obj.model.stepRandomWalk(dtSim);

            % Render agent motion (targets/edges are static)
            obj.renderer.renderAgents(obj.model);
            obj.publishTime();
        end

        function stopTimer(obj)
            obj.isRunning = false;
            if ~isempty(obj.timerObj) && isvalid(obj.timerObj)
                if strcmp(obj.timerObj.Running,'on')
                    stop(obj.timerObj);
                end
            end
        end

        function publishTime(obj)
            if ~isempty(obj.timeCallback)
                obj.timeCallback(obj.clock.currentTime, obj.clock.endTime);
            end
        end


        function say(obj, msg)
            if ~isempty(obj.statusCallback)
                obj.statusCallback(char(msg));
            end
        end
    end
end
