class WhatsappGroup < ApplicationRecord
  LIST_STYLES = %w[numbered bullet dash plain].freeze
  LOCALES = %w[pt-BR en es].freeze
  LIST_VARIABLES = %w[lista mencoes].freeze

  has_many :group_participants, dependent: :destroy
  has_many :member_lists, dependent: :destroy
  has_many :templates, dependent: :destroy
  has_many :flows, dependent: :destroy
  has_many :group_rules, dependent: :destroy

  validates :jid, presence: true, uniqueness: true
  validates :list_style, inclusion: { in: LIST_STYLES }
  validates :locale, inclusion: { in: LOCALES }

  # Idioma das mensagens geradas pela Cynth.ia neste grupo (meses, assinatura padrão). Ao trocar,
  # quem ainda usa a assinatura padrão do idioma antigo recebe a do novo.
  before_save :translate_default_signature, if: :will_save_change_to_locale?

  # Linhas do formulário {nome, valor} → { "nome" => "valor" }. Nome vira chave de variável
  # válida ({{nome}}); linhas sem nome são descartadas.
  def self.variables_from(rows)
    rows.to_h.values.each_with_object({}) do |row, variables|
      key = Template.key_for(row[:name])
      variables[key] = row[:value].to_s if key.present?
    end
  end

  # Linhas do formulário {id, name}: com id renomeia (nome vazio apaga), sem id cria.
  def update_lists!(rows)
    transaction do
      rows.to_h.values.each do |row|
        name = row[:name].to_s.strip
        list = member_lists.find_by(id: row[:id]) if row[:id].present?

        if list
          name.empty? ? list.destroy! : list.update!(name: name)
        elsif name.present?
          member_lists.create!(name: name)
        end
      end
    end
  end

  # Assinatura das respostas a comandos: uma das opções separadas por "|", sorteada a cada
  # mensagem (vazia desliga). Variar também evita o bloqueio de mensagem idêntica do SendGuard.
  def signature_sample
    signature.to_s.split("|").map(&:strip).compact_blank.sample
  end

  def self.default_signature(locale)
    I18n.t("cynthia.signature", locale: locale)
  end

  # RF-28: quando o aviso de IA de terceiro saiu neste grupo (nil = ainda não). Usado no selo de /groups/:id.
  def ai_notice_sent_at
    MessageLog.where(group_jid: jid, kind: MessageLog::AI_NOTICE, status: "sent").minimum(:sent_at)
  end

  def rule(kind)
    group_rules.find { |rule| rule.kind == kind }
  end

  # Quem mandou um comando ou reagiu, mesmo que ainda não tenha sido sincronizado.
  def participant_for!(jid, push_name = nil)
    group_participants.find_or_create_by!(jid: jid) do |participant|
      participant.name = push_name.presence
      participant.phone_number = jid.split("@").first.split(":").first
    end
  end

  # Comparação de nomes digitados no grupo: sem acento, caixa nem pontuação.
  def self.normalize_name(text)
    I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9 ]/, " ").squish
  end

  # Membro pelo número (@5511...) ou pelo nome na lista / nome no WhatsApp ("@~Nome" também).
  # Nome ambíguo (dois membros) não casa com ninguém. people evita reconsultar em laços.
  def participant_named(name, people: GroupParticipant.where(whatsapp_group_id: id).to_a)
    digits = name[/\A@?(\d{8,})\z/, 1]
    return people.find { |participant| participant.phone_number == digits } if digits

    key = self.class.normalize_name(name.delete_prefix("@").delete_prefix("~"))
    matches = people.select { |participant| [ participant.display_name, participant.name ].compact.any? { |label| self.class.normalize_name(label) == key } }
    matches.first if matches.one?
  end

  def members_of(list_keys)
    group_participants.joins(:member_lists).where(member_lists: { key: list_keys }).distinct
      .sort_by { |participant| participant.label.to_s.downcase }
  end

  def format_list(items)
    return list_empty_text if items.empty?

    items.each_with_index.map do |item, index|
      prefix = { "numbered" => "#{index + 1}. ", "bullet" => "• ", "dash" => "- " }.fetch(list_style, "")
      "#{prefix}#{item}"
    end.join("\n")
  end

  # {{lista:chave}} / {{mencoes:chave}}; mencoes acrescenta as pessoas em mentioned_jids.
  def render_list_variable(name, list_keys, mentioned_jids)
    people = members_of(list_keys)
    return format_list(people.map(&:label)) if name == "lista"

    mentioned_jids.concat(people.map(&:jid))
    format_list(people.map { |participant| "@#{participant.phone_number}" })
  end

  def provides_variable?(key)
    list_variable?(key) || group_rules.any? { |rule| rule.handler.provides_variable?(rule, key) }
  end

  def render_variable(key, mentioned_jids)
    name, list_key = key.split(":", 2)
    return render_list_variable(name, [ list_key ], mentioned_jids) if list_variable?(key)

    group_rules.each do |rule|
      value = rule.handler.render_variable(rule, key, mentioned_jids)
      return value if value
    end
    nil
  end

  private

  def translate_default_signature
    old_locale = locale_was || "pt-BR"
    self.signature = self.class.default_signature(locale) if signature == self.class.default_signature(old_locale)
  end

  def list_variable?(key)
    name, list_key = key.split(":", 2)
    LIST_VARIABLES.include?(name) && member_lists.any? { |list| list.key == list_key }
  end
end
