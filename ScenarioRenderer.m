classdef ScenarioRenderer < handle
    properties
        ax

        % Target visuals (we draw targets ourselves for consistent look)
        targetScatterHandle = gobjects(1)
        targetTextHandles   = gobjects(0)

        % Edge preview line (dashed)
        edgePreviewLine
    end

    methods
        function obj = ScenarioRenderer(ax)
            obj.ax = ax;

            hold(obj.ax,'on');
            obj.edgePreviewLine = line(obj.ax, [NaN NaN], [NaN NaN], ...
                'LineStyle','--','LineWidth',1, 'HitTest','off');
            hold(obj.ax,'off');
        end

        function clearAxes(obj)
            cla(obj.ax);

            obj.targetScatterHandle = gobjects(1);
            obj.targetTextHandles   = gobjects(0);

            hold(obj.ax,'on');
            obj.edgePreviewLine = line(obj.ax, [NaN NaN], [NaN NaN], ...
                'LineStyle','--','LineWidth',1, 'HitTest','off');
            hold(obj.ax,'off');

            grid(obj.ax,'on'); axis(obj.ax,'equal');
            xlim(obj.ax,[0 100]); ylim(obj.ax,[0 100]);
        end

        function resetEdgePreview(obj)
            obj.edgePreviewLine.XData = [NaN NaN];
            obj.edgePreviewLine.YData = [NaN NaN];
        end

        function updateEdgePreview(obj, p1, p2)
            obj.edgePreviewLine.XData = [p1(1) p2(1)];
            obj.edgePreviewLine.YData = [p1(2) p2(2)];
        end

        function renderAll(obj, model)
            obj.renderTargets(model);
            obj.renderEdges(model);
            obj.renderAgents(model);
        end

        function renderTargets(obj, model)
            % delete old labels
            if ~isempty(obj.targetTextHandles)
                try
                    delete(obj.targetTextHandles(ishandle(obj.targetTextHandles)));
                catch
                end
            end
            obj.targetTextHandles = gobjects(0);

            if isempty(model.targets)
                if ~isempty(obj.targetScatterHandle) && isgraphics(obj.targetScatterHandle)
                    delete(obj.targetScatterHandle);
                end
                obj.targetScatterHandle = gobjects(1);
                return;
            end

            P = reshape([model.targets.position], 2, []).';

            hold(obj.ax,'on');

            if isempty(obj.targetScatterHandle) || ~isgraphics(obj.targetScatterHandle)
                obj.targetScatterHandle = scatter(obj.ax, P(:,1), P(:,2), 110, ...
                    'Marker','o', 'MarkerFaceColor',[0 0.4 1], 'MarkerEdgeColor','k', ...
                    'LineWidth', 1.2, 'HitTest','off');
            else
                obj.targetScatterHandle.XData = P(:,1);
                obj.targetScatterHandle.YData = P(:,2);
            end

            for i = 1:size(P,1)
                obj.targetTextHandles(i) = text(obj.ax, P(i,1)+1.0, P(i,2)+1.0, ...
                    sprintf('T%d', i), ...
                    'FontWeight','bold', 'Color','k', 'FontSize', 10, ...
                    'HitTest','off'); %#ok<AGROW>
            end

            hold(obj.ax,'off');
        end

        function renderAgents(obj, model)
            for k = 1:numel(model.agents)
                a = model.agents(k);
                if isempty(a.graphicHandle) || ~isgraphics(a.graphicHandle)
                    hold(obj.ax,'on');
                    a.draw(obj.ax);
                    hold(obj.ax,'off');
                else
                    a.updatePosition();
                end
            end
        end

        function renderEdges(obj, model)
            for k = 1:numel(model.edges)
                e = model.edges(k);
                if isempty(e.lineHandle) || ~isgraphics(e.lineHandle)
                    hold(obj.ax,'on');
                    e.draw(obj.ax); % uses your Edge.draw()
                    hold(obj.ax,'off');
                else
                    % could update geometry here if targets move
                end
            end
        end
    end
end
