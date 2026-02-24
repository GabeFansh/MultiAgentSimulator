classdef ScenarioRenderer < handle
    properties
        ax

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
            try
                delete(allchild(obj.ax));
            catch
                % Fallback if something goes wrong
                cla(obj.ax,'reset');
            end

            % Restore axes look/limits
            grid(obj.ax,'on');
            axis(obj.ax,'equal');
            xlim(obj.ax,[0 100]); ylim(obj.ax,[0 100]);
            title(obj.ax,'Click to add targets/agents/edges');

            % Recreate preview line
            hold(obj.ax,'on');
            obj.edgePreviewLine = line(obj.ax, [NaN NaN], [NaN NaN], ...
                'LineStyle','--','LineWidth',1, 'HitTest','off');
            hold(obj.ax,'off');
        end

        function resetEdgePreview(obj)
            if ~isempty(obj.edgePreviewLine) && isgraphics(obj.edgePreviewLine)
                obj.edgePreviewLine.XData = [NaN NaN];
                obj.edgePreviewLine.YData = [NaN NaN];
            end
        end

        function updateEdgePreview(obj, p1, p2)
            if ~isempty(obj.edgePreviewLine) && isgraphics(obj.edgePreviewLine)
                obj.edgePreviewLine.XData = [p1(1) p2(1)];
                obj.edgePreviewLine.YData = [p1(2) p2(2)];
            end
        end

        function renderAll(obj, model)
            obj.renderEdges(model);
            obj.renderTargets(model);
            obj.renderAgents(model);
        end

        function renderTargets(obj, model)
            for k = 1:numel(model.targets)
                t = model.targets(k);

                needsDraw = isempty(t.graphicHandle) || ~isgraphics(t.graphicHandle) || ...
                            isempty(t.barHandle)     || ~isgraphics(t.barHandle)     || ...
                            isempty(t.labelHandle)   || ~isgraphics(t.labelHandle);

                if needsDraw
                    hold(obj.ax,'on');
                    t.draw(obj.ax);
                    hold(obj.ax,'off');
                end
            end
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
                    e.draw(obj.ax);
                    hold(obj.ax,'off');
                end
            end
        end
    end
end