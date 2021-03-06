defmodule BlueJetWeb.ProductCollectionMembershipView do
  use BlueJetWeb, :view
  use JaSerializer.PhoenixView

  attributes [
    :sort_index,
    :inserted_at,
    :updated_at
  ]

  has_one :collection, serializer: BlueJetWeb.ProductCollectionView, identifiers: :always
  has_one :product, serializer: BlueJetWeb.ProductView, identifiers: :always

  def type(_, _conn) do
    "ProductCollectionMembership"
  end

  def collection(membership = %{ collection: %Ecto.Association.NotLoaded{} }, _) do
    case membership.collection_id do
      nil -> nil
      _ -> %{ type: "ProductCollection", id: membership.collection_id }
    end
  end
  def collection(membership, _), do: Map.get(membership, :collection)

  def product(membership = %{ product: %Ecto.Association.NotLoaded{} }, _) do
    case membership.product_id do
      nil -> nil
      _ -> %{ type: "Product", id: membership.product_id }
    end
  end
  def product(membership, _), do: Map.get(membership, :product)
end
