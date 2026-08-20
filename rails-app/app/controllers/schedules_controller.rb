class SchedulesController < ApplicationController
  before_action :set_schedule, only: %i[edit update destroy send_test]

  def index
    @schedules = Schedule.includes(:template, :whatsapp_group).order(:next_run_at)
  end

  def new
    @schedule = Schedule.new(timezone: "America/Sao_Paulo")
  end

  def create
    @schedule = Schedule.new(schedule_params)
    @schedule.next_run_at = ScheduleCalculator.next_run(@schedule) if @schedule.valid?

    if @schedule.save
      redirect_to schedules_path, notice: "Agendamento criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @schedule.assign_attributes(schedule_params)
    @schedule.next_run_at = ScheduleCalculator.next_run(@schedule) if @schedule.valid?

    if @schedule.save
      redirect_to schedules_path, notice: "Agendamento atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @schedule.destroy
    redirect_to schedules_path, notice: "Agendamento removido."
  end

  def send_test
    SendScheduledMessageJob.perform_async(@schedule.id)
    redirect_to schedules_path, notice: "Envio de teste enfileirado."
  end

  def cron_preview
    @cron_expression = params[:cron_expression]
    @timezone = params[:timezone].presence || "America/Sao_Paulo"
    @cron = Fugit.parse_cron("#{@cron_expression} #{@timezone}") if @cron_expression.present?

    render layout: false
  end

  private

  def set_schedule
    @schedule = Schedule.find(params[:id])
  end

  def schedule_params
    params.require(:schedule).permit(
      :template_id, :whatsapp_group_id, :variables_json,
      :cron_expression, :run_at, :timezone, :active
    )
  end
end
