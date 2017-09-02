defmodule BlueJet.Storefront.Product do
  use BlueJet, :data

  use Trans, translates: [:name, :caption, :description, :custom_data], container: :translations

  alias BlueJet.Translation
  alias BlueJet.Storefront.ProductItem
  alias BlueJet.Storefront.Product
  alias BlueJet.Identity.Account
  alias BlueJet.FileStorage.ExternalFile
  alias BlueJet.FileStorage.ExternalFileCollection

  schema "products" do
    field :name, :string
    field :print_name, :string
    field :status, :string
    field :item_mode, :string, default: "any"
    field :caption, :string
    field :description, :string

    field :custom_data, :map, default: %{}
    field :translations, :map, default: %{}

    timestamps()

    belongs_to :account, Account
    belongs_to :avatar, ExternalFile
    has_many :items, ProductItem, on_delete: :delete_all
    has_many :external_file_collections, ExternalFileCollection, on_delete: :delete_all
  end

  def system_fields do
    [
      :id,
      :inserted_at,
      :updated_at
    ]
  end

  def writable_fields do
    Product.__schema__(:fields) -- system_fields()
  end

  def translatable_fields do
    Product.__trans__(:fields)
  end

  def castable_fields(%{ __meta__: %{ state: :built }}) do
    writable_fields()
  end
  def castable_fields(%{ __meta__: %{ state: :loaded }}) do
    writable_fields() -- [:account_id]
  end

  def validate(changeset) do
    changeset
    |> validate_required([:account_id, :name, :status, :item_mode])
    |> validate_assoc_account_scope(:avatar)
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

  def preload(struct_or_structs, targets) when length(targets) == 0 do
    struct_or_structs
  end
  def preload(struct_or_structs, targets) when is_list(targets) do
    [target | rest] = targets

    struct_or_structs
    |> Repo.preload(preload_keyword(target))
    |> Product.preload(rest)
  end

  def preload_keyword(:items) do
    [items: ProductItem.query()]
  end
  def preload_keyword({:items, [item_preloads]}) do
    [items: {ProductItem.query(), ProductItem.preload_keyword(item_preloads)}]
  end
  def preload_keyword(:avatar) do
    :avatar
  end
  def preload_keyword(:external_file_collections) do
    [external_file_collections: ExternalFileCollection.query()]
  end
end
