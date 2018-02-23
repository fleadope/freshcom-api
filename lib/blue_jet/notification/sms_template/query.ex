defmodule BlueJet.Notification.SmsTemplate.Query do
  use BlueJet, :query

  alias BlueJet.Notification.SmsTemplate

  @searchable_fields [
    :name,
    :to
  ]

  def default() do
    from st in SmsTemplate, order_by: [desc: :updated_at]
  end

  def for_account(query, account_id) do
    from st in query, where: st.account_id == ^account_id
  end

  def search(query, keyword, locale, default_locale) do
    search(query, @searchable_fields, keyword, locale, default_locale, SmsTemplate.translatable_fields())
  end

  def preloads(_, _) do
    []
  end
end