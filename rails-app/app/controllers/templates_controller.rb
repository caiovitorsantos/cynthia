class TemplatesController < ApplicationController
  before_action :set_template, only: %i[edit update destroy]

  def index
    @templates = Template.order(:name)
  end

  def new
    @template = Template.new
  end

  def create
    @template = Template.new(template_params)

    if @template.save
      redirect_to templates_path, notice: "Template criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      redirect_to templates_path, notice: "Template atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @template.destroy
      redirect_to templates_path, notice: "Template removido."
    else
      redirect_to templates_path, alert: "Não é possível remover: existem agendamentos usando este template."
    end
  end

  private

  def set_template
    @template = Template.find(params[:id])
  end

  def template_params
    params.require(:template).permit(:name, :body, :active, :attendance)
  end
end
