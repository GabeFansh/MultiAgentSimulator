classdef SimulationController < handle
    properties
        model
        renderer
        clock

        timerObj
        isRunning logical = false

        timeCallback       % @(t, tEnd) ...
        statusCallback     % @(msg) ...
        objectiveCallback  % @(t, J) ...
    end

    properties (Access=private)
        realPeriod = 0.03

        % Fast-forward responsiveness knobs
        renderEveryTicks = 200     % render agents every N sim steps during fast-forward
        drawnowEveryTicks = 200    % call drawnow limitrate every N sim steps
        maxTicksPerChunk = 5000    % chunk size to keep UI responsive

        % Jump-to-end knobs (accurate but minimal UI work)
        jumpPublishEveryTicks = 50   % publish objective/time every N ticks during jump
        jumpDoDrawnow logical = true % set false to be even faster (UI won't update until end)
    end

    methods
        function obj = SimulationController(model, renderer, clock, timeCb, statusCb, objCb)
            obj.model = model;
            obj.renderer = renderer;
            obj.clock = clock;

            obj.timeCallback = timeCb;
            obj.statusCallback = statusCb;
            obj.objectiveCallback = objCb;

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
                obj.reset();
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

        function reset(obj)
            obj.pause();
            obj.clock.reset();

            if ismethod(obj.model, 'resetSimulationState')
                obj.model.resetSimulationState();
            end

            obj.renderer.renderAll(obj.model);
            obj.publishTime();

            % objective at t=0
            if ~isempty(obj.objectiveCallback) && ismethod(obj.model, 'updateTargetsAndLogObjective')
                [~, JNow] = obj.model.updateTargetsAndLogObjective(obj.clock.currentTime, 0);
                obj.objectiveCallback(obj.clock.currentTime, JNow);
            end

            obj.say("Reset.");
        end

        function runToEnd(obj)
            % Visual fast-forward (accurate, but still updates plot every tick)
            obj.pause();
            if obj.clock.isFinished()
                obj.say("Already at end.");
                return;
            end

            obj.say("Fast-forwarding to end...");

            tickCounter = 0;

            while ~obj.clock.isFinished()
                stepsThisChunk = 0;

                while stepsThisChunk < obj.maxTicksPerChunk && ~obj.clock.isFinished()
                    dtSim = obj.clock.tick();
                    if dtSim <= 0, break; end

                    JNow = obj.doOneSimStep(dtSim);

                    % publish objective every tick (smooth curve)
                    obj.publishObjective(JNow);

                    tickCounter = tickCounter + 1;
                    stepsThisChunk = stepsThisChunk + 1;

                    if mod(tickCounter, obj.renderEveryTicks) == 0
                        obj.renderer.renderAgents(obj.model);
                    end

                    if mod(tickCounter, obj.drawnowEveryTicks) == 0
                        obj.publishTime();
                        drawnow limitrate;
                    end
                end

                obj.publishTime();
                drawnow limitrate;
            end

            obj.renderer.renderAgents(obj.model);

            % final objective at exact end time
            if ismethod(obj.model, 'updateTargetsAndLogObjective')
                [~, JNow] = obj.model.updateTargetsAndLogObjective(obj.clock.currentTime, 0);
                obj.publishObjective(JNow);
            end

            obj.publishTime();
            obj.say("Reached end.");
        end

        function jumpToEndAccurate(obj)
            % “Instant-feeling” jump: still simulates EVERY tick for correctness,
            % but minimizes UI/plot work.
            obj.pause();
            if obj.clock.isFinished()
                obj.say("Already at end.");
                return;
            end

            obj.say("Jumping to end (accurate)...");

            tickCounter = 0;
            lastJ = 0;

            while ~obj.clock.isFinished()
                stepsThisChunk = 0;

                while stepsThisChunk < obj.maxTicksPerChunk && ~obj.clock.isFinished()
                    dtSim = obj.clock.tick();
                    if dtSim <= 0, break; end

                    lastJ = obj.doOneSimStep(dtSim);
                    tickCounter = tickCounter + 1;
                    stepsThisChunk = stepsThisChunk + 1;

                    % publish MUCH less frequently to keep it fast
                    if mod(tickCounter, obj.jumpPublishEveryTicks) == 0
                        obj.publishObjective(lastJ);
                        obj.publishTime();
                        if obj.jumpDoDrawnow
                            drawnow limitrate;
                        end
                    end
                end

                % end-of-chunk update (still minimal)
                obj.publishTime();
                if obj.jumpDoDrawnow
                    drawnow limitrate;
                end
            end

            % final render + final objective at exact end time
            obj.renderer.renderAgents(obj.model);

            if ismethod(obj.model, 'updateTargetsAndLogObjective')
                [~, lastJ] = obj.model.updateTargetsAndLogObjective(obj.clock.currentTime, 0);
            end
            obj.publishObjective(lastJ);
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
    end

    methods (Access=private)
        function JNow = doOneSimStep(obj, dtSim)
            % Move agents
            obj.model.stepRandomWalk(dtSim);

            % Update targets + objective (authoritative)
            JNow = 0;
            if ismethod(obj.model, 'updateTargetsAndLogObjective')
                [~, JNow] = obj.model.updateTargetsAndLogObjective(obj.clock.currentTime, dtSim);
            end
        end

        function onTimerTick(obj)
            if obj.clock.isFinished()
                obj.pause();
                obj.say("Reached end.");
                return;
            end

            dtSim = obj.clock.tick();
            if dtSim <= 0
                obj.pause();
                obj.say("Reached end.");
                return;
            end

            JNow = obj.doOneSimStep(dtSim);
            obj.publishObjective(JNow);

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

        function publishObjective(obj, JNow)
            if ~isempty(obj.objectiveCallback)
                obj.objectiveCallback(obj.clock.currentTime, JNow);
            end
        end

        function say(obj, msg)
            if ~isempty(obj.statusCallback)
                obj.statusCallback(char(msg));
            end
        end
    end
end