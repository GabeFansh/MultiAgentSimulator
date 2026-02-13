classdef MainUI < handle
    properties
        fig
        ax
        speedField
        modeLabel
        statusLabel

        model
        renderer
        controller
    end

    methods
        function obj = MainUI()
            obj.buildUI();

            obj.model = ScenarioModel();
            obj.renderer = ScenarioRenderer(obj.ax);
            obj.controller = GraphEditController(obj.model, obj.renderer, @(m)obj.setStatus(m));

            % Set motion callback ONLY AFTER controller exists
            obj.fig.WindowButtonMotionFcn = @(~,~)obj.safeOnMouseMove();

            obj.controller.setMode("idle");
            obj.renderer.renderAll(obj.model);
        end
    end

    methods (Access=private)
        function buildUI(obj)
            obj.fig = uifigure('Name','Refactored Sketch UI', 'Position',[100 100 1200 750]);
            p = uipanel(obj.fig, 'Title','Tools', 'Position',[10 10 260 730]);

            obj.ax = uiaxes(obj.fig, 'Position',[290 10 900 730]);
            grid(obj.ax,'on'); axis(obj.ax,'equal');
            xlim(obj.ax,[0 100]); ylim(obj.ax,[0 100]);
            title(obj.ax,'Click to add targets/agents/edges');

            % Buttons (DO NOT call obj.controller.* here)
            uibutton(p,'Text','Add Target','Position',[20 650 220 42], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("addTarget"));

            uibutton(p,'Text','Add Agent (on target)','Position',[20 600 220 42], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("addAgent"));

            uibutton(p,'Text','Add Edge (pick 2 targets)','Position',[20 550 220 42], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("addEdge"));

            uibutton(p,'Text','Idle','Position',[20 500 220 36], ...
                'ButtonPushedFcn', @(~,~)obj.setMode("idle"));

            uibutton(p,'Text','Clear All','Position',[20 440 220 40], ...
                'ButtonPushedFcn', @(~,~)obj.onClearAll());

            % Speed
            uilabel(p,'Text','Agent speed:','Position',[20 390 90 22]);
            obj.speedField = uieditfield(p,'numeric','Value',5,'Limits',[0.01 Inf], ...
                'Position',[115 386 125 30]);

            obj.modeLabel = uilabel(p,'Text','Mode: idle', 'Position',[20 340 220 26], ...
                'FontWeight','bold');

            obj.statusLabel = uilabel(p,'Text','', 'Position',[20 270 220 60], ...
                'WordWrap','on');

            % Canvas click callback
            obj.ax.PickableParts = 'all';
            obj.ax.HitTest = 'on';
            obj.ax.ButtonDownFcn = @(ax,~)obj.onAxesClick(ax);

            % IMPORTANT: do NOT set WindowButtonMotionFcn here
        end

        function onClearAll(obj)
            if isempty(obj.controller) || ~isa(obj.controller,'GraphEditController')
                return;
            end
            obj.controller.clearAll();
            obj.setStatus('Cleared.');
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

        function onAxesClick(obj, ax)
            if isempty(obj.controller) || ~isa(obj.controller,'GraphEditController')
                return;
            end
            cp = ax.CurrentPoint;
            pos = [cp(1,1) cp(1,2)];
            obj.controller.onCanvasClick(pos, obj.speedField.Value);
        end

        function safeOnMouseMove(obj)
            if isempty(obj.controller) || ~isa(obj.controller,'GraphEditController')
                return;
            end
            if isempty(obj.ax) || ~isvalid(obj.ax)
                return;
            end
            % CurrentPoint is always available; just forward
            cp = obj.ax.CurrentPoint;
            pos = [cp(1,1) cp(1,2)];
            obj.controller.onCanvasMove(pos);
        end
    end
end
