defmodule BlueJetWeb.DepositableView do
  use BlueJetWeb, :view
  use JaSerializer.PhoenixView

  attributes [
    :code,
    :status,
    :name,
    :label,

    :print_name,
    :amount,
    :target_type,

    :caption,
    :description,
    :custom_data,

    :inserted_at,
    :updated_at
  ]

  has_one :avatar, serializer: BlueJetWeb.ExternalFileView, identifiers: :always
  has_many :external_file_collections, serializer: BlueJetWeb.ExternalFileCollectionView, identifiers: :when_included

  def type do
    "Depositable"
  end

  def avatar(%{ avatar_id: nil }, _), do: nil
  def avatar(%{ avatar_id: avatar_id, avatar: nil }, _), do: %{ id: avatar_id, type: "ExternalFile" }
  def avatar(%{ avatar: avatar }, _), do: avatar
end
