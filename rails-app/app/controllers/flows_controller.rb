class FlowsController < ApplicationController
  before_action :set_group
  before_action :set_flow, only: %i[edit update destroy run]

  def new
    @flow = @group.flows.new(trigger: params[:trigger].presence || "schedule")
  end

  def create
    @flow = @group.flows.new(flow_params)

    if @flow.save
      redirect_to group_path(@group, anchor: "fluxos"), notice: t(".notice")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @flow.update(flow_params)
      redirect_to group_path(@group, anchor: "fluxos"), notice: t(".notice")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @flow.destroy
    redirect_to group_path(@group, anchor: "fluxos"), notice: t(".notice")
  end

  # Executa agora, sem mexer na próxima execução da rotina. Passos que dependem de quem mandou
  # o comando são pulados.
  def run
    RunFlowJob.perform_async(@flow.id)
    redirect_to group_path(@group, anchor: "fluxos"), notice: t(".notice", name: @flow.name)
  end

  def cron_preview
    @cron_expression = params.dig(:flow, :cron_expression)
    @timezone = params.dig(:flow, :timezone).presence || "America/Sao_Paulo"
    @cron = Fugit.parse_cron("#{@cron_expression} #{@timezone}") if @cron_expression.present?

    render layout: false
  end

  private

  def set_group
    @group = WhatsappGroup.find(params[:group_id])
  end

  def set_flow
    @flow = @group.flows.find(params[:id])
  end

  def flow_params
    permitted = params.require(:flow).permit(:name, :trigger, :command, :cron_expression, :run_at, :timezone, :active)
    permitted.merge(steps: Flow.steps_from(params[:flow].fetch(:steps, {}).permit!))
  end
end
