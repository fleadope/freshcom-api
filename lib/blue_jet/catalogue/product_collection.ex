defmodule BlueJet.Catalogue.ProductCollection do
  use BlueJet, :data

  use Trans, translates: [:name, :custom_data], container: :translations

  alias BlueJet.Translation
  alias BlueJet.Catalogue.Product
  alias BlueJet.Catalogue.ProductCollection
  alias BlueJet.Catalogue.ProductCollectionMembership

  schema "product_collections" do
    field :account_id, Ecto.UUID

    field :code, :string
    field :status, :string
    field :name, :string
    field :label, :string
    field :sort_index, :integer

    field :custom_data, :map, default: %{}
    field :translations, :map, defualt: %{}

    timestamps()

    has_many :memberships, ProductCollectionMembership, foreign_key: :collection_id
    has_many :products, through: [:memberships, :product]
  end

  def system_fields do
    [
      :id,
      :inserted_at,
      :updated_at
    ]
  end

  def writable_fields do
    ProductCollection.__schema__(:fields) -- system_fields()
  end

  def translatable_fields do
    ProductCollection.__trans__(:fields)
  end

  def castable_fields(%{ __meta__: %{ state: :built }}) do
    writable_fields()
  end
  def castable_fields(%{ __meta__: %{ state: :loaded }}) do
    writable_fields() -- [:account_id]
  end

  def validate(changeset) do
    changeset
    |> validate_required([:account_id, :status, :name])
    |> foreign_key_constraint(:account_id)
  end

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}, locale \\ "en") do
    struct
    |> cast(params, castable_fields(struct))
    |> validate()
    |> Translation.put_change(translatable_fields(), locale)
  end

  defmodule Query do
    use BlueJet, :query

    def default() do
      from(pc in ProductCollection, order_by: [desc: pc.updated_at])
    end

    def for_account(query, account_id) do
      from(pc in query, where: pc.account_id == ^account_id)
    end

    def preloads({:products, product_preloads}, options = [role: role]) when role == "guest" or role == "customer" do
      query = Product.Query.default() |> Product.Query.active()
      [products: {query, Product.Query.preloads(product_preloads, options)}]
    end

    def preloads({:products, product_preloads}, options = [role: _]) do
      query = Product.Query.default()
      [products: {query, Product.Query.preloads(product_preloads, options)}]
    end

    def preloads({:memberships, membership_preloads}, options = [role: role]) when role == "guest" or role == "customer" do
      query = ProductCollectionMembership.Query.default() |> ProductCollectionMembership.Query.with_active_product()
      [memberships: {query, ProductCollectionMembership.Query.preloads(membership_preloads, options)}]
    end

    def preloads({:memberships, membership_preloads}, options = [role: _]) do
      query = ProductCollectionMembership.Query.default()
      [memberships: {query, ProductCollectionMembership.Query.preloads(membership_preloads, options)}]
    end
  end
end