class TemplatesController < ApplicationController
  before_action :set_group
  before_action :set_template, only: %i[edit update destroy]

  def new
    @template = @group.templates.new
  end

  def create
    @template = @group.templates.new(template_params)

    if @template.save
      redirect_to group_path(@group, anchor: "templates"), notice: "Template criado. Que texto. Uau."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      redirect_to group_path(@group, anchor: "templates"), notice: "Template atualizado. Mesma mensagem, outras palavras."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @template.destroy
      redirect_to group_path(@group, anchor: "templates"), notice: "Template apagado. Menos uma coisa pra eu mandar."
    else
      redirect_to group_path(@group, anchor: "templates"), alert: "Não dá pra apagar: #{@template.errors.full_messages.to_sentence}. Tira dos fluxos primeiro."
    end
  end

  private

  def set_group
    @group = WhatsappGroup.find(params[:group_id])
  end

  def set_template
    @template = @group.templates.find(params[:id])
  end

  def template_params
    params.require(:template).permit(:name, :body, :active)
  end
end
