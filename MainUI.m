classdef MainUI < handle
    properties
        fig
        ax

        % Tools panel widgets
        speedField
        modeLabel
        statusLabel

        % Time control widgets
        timeLabel
        endTimeField
        dtField
        timeScaleSlider

        % Core objects
        model
        renderer
        controller

        clock
        sim

        objectiveWin

        gridStep = 5;
        snapTargets = true;
    end

    methods
        function obj = MainUI()
            obj.buildUI();

            obj.model = ScenarioModel();
            obj.renderer = ScenarioRenderer(obj.ax);
            obj.controller = GraphEditController(obj.model, obj.renderer, @(m)obj.setStatus(m));

            obj.objectiveWin = ObjectivePlotWindow();

            % Simulation
            obj.clock = SimulationClock(obj.endTimeField.Value, obj.dtField.Value);
            obj.sim = SimulationController(obj.model, obj.renderer, obj.clock, ...
                @(t,tEnd)obj.setTime(t,tEnd), ...
                @(m)obj.setStatus(m), ...
                @(t,J)obj.objectiveWin.addPoint(t,J));

            % Mouse move for edge preview (after controller exists)
            obj.fig.WindowButtonMotionFcn = @(~,~)obj.safeOnMouseMove();

            obj.controller.setMode("idle");
            obj.renderer.renderAll(obj.model);
            obj.setTime(0, obj.clock.endTime);
        end
    end

    methods (Access=private)
        function buildUI(obj)
            obj.fig = uifigure('Name','Refactored Sketch UI + Time Control', ...
                'Position',[100 100 1200 750]);

            % Tools panel (top-left)
            p = uipanel(obj.fig, 'Title','Tools', 'Position',[10 270 260 470]);

            % Time control panel (bottom-left)
            tp = uipanel(obj.fig, 'Title','Time Control', 'Position',[10 10 260 250]);

            % Axes
            obj.ax = uiaxes(obj.fig, 'Position',[290 10 900 730]);
            try
                disableDefaultInteractivity(obj.ax);
            catch
            end
            grid(obj.ax,'on'); axis(obj.ax,'equal');
            xlim(obj.ax,[0 100]); ylim(obj.ax,[0 100]);
            title(obj.ax,'Click to add targets/agents/edges');

            % ----- Tools buttons -----
            uibutton(p,'Text','Add Target','Position',[20 380 220 42], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("addTarget"));

            uibutton(p,'Text','Add Agent (on target)','Position',[20 330 220 42], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("addAgent"));

            uibutton(p,'Text','Add Edge (pick 2 targets)','Position',[20 280 220 42], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("addEdge"));

            uibutton(p,'Text','Idle','Position',[20 235 220 36], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("idle"));

            uibutton(p,'Text','Clear All','Position',[20 185 220 40], ...
                'ButtonPushedFcn', @(~,~)obj.onClearAll());

            % NEW: Layout save/load
            uibutton(p,'Text','Save Layout...','Position',[20 145 105 32], ...
                'ButtonPushedFcn', @(~,~)obj.onSaveLayout());

            uibutton(p,'Text','Load Layout...','Position',[135 145 105 32], ...
                'ButtonPushedFcn', @(~,~)obj.onLoadLayout());

            % Agent speed
            uilabel(p,'Text','Agent speed:','Position',[20 115 90 22]);
            obj.speedField = uieditfield(p,'numeric','Value',5,'Limits',[0.01 Inf], ...
                'Position',[115 111 125 30]);

            obj.modeLabel = uilabel(p,'Text','Mode: idle', ...
                'Position',[20 82 220 26], 'FontWeight','bold');

            obj.statusLabel = uilabel(p,'Text','', ...
                'Position',[20 10 220 70], 'WordWrap','on');

            % Canvas click callback
            obj.ax.PickableParts = 'all';
            obj.ax.HitTest = 'on';
            obj.ax.ButtonDownFcn = @(ax,~)obj.onAxesClick(ax);

            % ----- Time control -----
            obj.timeLabel = uilabel(tp,'Text','t = 0.00 / 60.00', ...
                'Position',[20 200 220 22], 'FontWeight','bold');

            uibutton(tp,'Text','Play','Position',[20 155 100 35], ...
                'ButtonPushedFcn', @(~,~)obj.sim.play());

            uibutton(tp,'Text','Pause','Position',[140 155 100 35], ...
                'ButtonPushedFcn', @(~,~)obj.sim.pause());

            uibutton(tp,'Text','Run to End','Position',[20 115 220 35], ...
                'ButtonPushedFcn', @(~,~)obj.sim.runToEnd());

            % Reset time (restart same scenario)
            uibutton(tp,'Text','Reset Time','Position',[20 80 220 30], ...
                'ButtonPushedFcn', @(~,~)obj.onResetSimulation());

            uilabel(tp,'Text','End time:','Position',[20 52 60 22]);
            obj.endTimeField = uieditfield(tp,'numeric','Value',60,'Limits',[0 Inf], ...
                'Position',[85 48 70 28], ...
                'ValueChangedFcn', @(s,~)obj.sim.setEndTime(s.Value));

            uilabel(tp,'Text','dt:','Position',[165 52 20 22]);
            obj.dtField = uieditfield(tp,'numeric','Value',0.05,'Limits',[1e-4 Inf], ...
                'Position',[190 48 50 28], ...
                'ValueChangedFcn', @(s,~)obj.sim.setDt(s.Value));

            uilabel(tp,'Text','Speed:','Position',[20 20 50 22]);
            obj.timeScaleSlider = uislider(tp, ...
                'Limits',[0 10], 'Value',1, ...
                'Position',[75 30 160 3], ...
                'ValueChangedFcn', @(s,~)obj.sim.setTimeScale(s.Value));
        end

        function onSaveLayout(obj)
            if isempty(obj.model) || ~isa(obj.model,'ScenarioModel') || ~ismethod(obj.model,'exportLayout')
                obj.setStatus("ScenarioModel.exportLayout() not found.");
                return;
            end

            s = obj.model.exportLayout();

            [f,d] = uiputfile('*.mat','Save layout as');
            if isequal(f,0)
                obj.setStatus("Save cancelled.");
                return;
            end

            try
                save(fullfile(d,f), 's');
                obj.setStatus("Saved layout: " + string(fullfile(d,f)));
            catch ME
                obj.setStatus("Save failed: " + string(ME.message));
            end
        end

        function onLoadLayout(obj)
            if isempty(obj.model) || ~isa(obj.model,'ScenarioModel') || ~ismethod(obj.model,'importLayout')
                obj.setStatus("ScenarioModel.importLayout() not found.");
                return;
            end

            [f,d] = uigetfile('*.mat','Load layout');
            if isequal(f,0)
                obj.setStatus("Load cancelled.");
                return;
            end

            try
                tmp = load(fullfile(d,f), 's');
                if ~isfield(tmp,'s')
                    obj.setStatus("Selected file does not contain variable 's'.");
                    return;
                end

                % stop simulation first
                if ~isempty(obj.sim) && isa(obj.sim,'SimulationController')
                    obj.sim.pause();
                end

                % import scenario
                obj.model.importLayout(tmp.s);

                % refresh visuals
                if ~isempty(obj.renderer) && isa(obj.renderer,'ScenarioRenderer')
                    obj.renderer.clearAxes();
                    obj.renderer.renderAll(obj.model);
                end

                % reset plot + simulation time/state
                if ~isempty(obj.objectiveWin) && isvalid(obj.objectiveWin)
                    obj.objectiveWin.reset();
                    obj.objectiveWin.addPoint(0,0);
                end

                if ~isempty(obj.sim) && isa(obj.sim,'SimulationController')
                    obj.sim.reset();
                else
                    if ~isempty(obj.clock)
                        obj.clock.reset();
                        obj.setTime(0, obj.clock.endTime);
                    end
                end

                obj.controller.setMode("idle");
                obj.setStatus("Loaded layout: " + string(fullfile(d,f)));

            catch ME
                obj.setStatus("Load failed: " + string(ME.message));
            end
        end

        function onResetSimulation(obj)
            % Reset plot
            if ~isempty(obj.objectiveWin) && isvalid(obj.objectiveWin)
                obj.objectiveWin.reset();
                obj.objectiveWin.addPoint(0,0);
            end

            % Reset sim (keeps scenario, resets time + agent positions + target uncertainty)
            if ~isempty(obj.sim) && isa(obj.sim,'SimulationController')
                obj.sim.reset();
            end
            obj.setStatus('Reset simulation + objective plot.');
        end

        function onClearAll(obj)
            % Clear All = wipe scenario completely.
            if ~isempty(obj.sim) && isa(obj.sim,'SimulationController')
                obj.sim.pause();
            end

            if ~isempty(obj.controller) && isa(obj.controller,'GraphEditController')
                obj.controller.clearAll();
            end

            if ~isempty(obj.objectiveWin) && isvalid(obj.objectiveWin)
                obj.objectiveWin.reset();
                obj.objectiveWin.addPoint(0,0);
            end

            if ~isempty(obj.clock)
                obj.clock.reset();
                obj.setTime(0, obj.clock.endTime);
            end

            obj.setStatus('Cleared everything.');
        end

        function setMode(obj, m)
            obj.modeLabel.Text = "Mode: " + string(m);
            if isempty(obj.controller) || ~isa(obj.controller,'GraphEditController')
                return;
            end
            obj.controller.setMode(m);
        end

        function setStatus(obj, msg)
            obj.statusLabel.Text = msg;
        end

        function setTime(obj, t, tEnd)
            if isempty(obj.timeLabel) || ~isvalid(obj.timeLabel)
                return;
            end
            obj.timeLabel.Text = sprintf('t = %.2f / %.2f', t, tEnd);
        end

        function onAxesClick(obj, ax)
            if isempty(obj.controller) || ~isa(obj.controller,'GraphEditController')
                return;
            end
            cp = ax.CurrentPoint;
            pos = [cp(1,1) cp(1,2)];

            % Update all agents' speeds from UI field
            if ~isempty(obj.model) && ~isempty(obj.model.agents)
                for k = 1:numel(obj.model.agents)
                    obj.model.agents(k).speed = obj.speedField.Value;
                end
            end

            obj.controller.onCanvasClick(pos, obj.speedField.Value);
        end

        function safeOnMouseMove(obj)
            if isempty(obj.controller) || ~isa(obj.controller,'GraphEditController')
                return;
            end
            if isempty(obj.ax) || ~isvalid(obj.ax)
                return;
            end
            cp = obj.ax.CurrentPoint;
            pos = [cp(1,1) cp(1,2)];
            obj.controller.onCanvasMove(pos);
        end
    end
end