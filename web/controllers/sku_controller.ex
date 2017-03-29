defmodule BlueJet.SkuController do
  use BlueJet.Web, :controller

  alias BlueJet.Sku
  alias JaSerializer.Params

  plug :scrub_params, "data" when action in [:create, :update]

  def index(conn, _params) do
    query = Sku
            |> paginate(size: conn.assigns[:page_size], number: conn.assigns[:page_number])
    skus = Repo.all(query)

    total_count = Repo.aggregate(Sku, :count, :id)
    result_count = Repo.aggregate(Sku, :count, :id)

    meta = %{
      totalCount: total_count,
      resultCount: result_count
    }

    render(conn, "index.json-api", data: skus, opts: [meta: meta])
  end

  def create(conn, %{"data" => data = %{"type" => "sku", "attributes" => _sku_params}}) do
    changeset = Sku.changeset(%Sku{}, conn.assigns[:locale], Params.to_attributes(data))

    case Repo.insert(changeset) do
      {:ok, sku} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", sku_path(conn, :show, sku))
        |> render("show.json-api", data: sku)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    sku = Sku
          |> Repo.get!(id)
          |> translate(conn.assigns[:locale])

    render(conn, "show.json-api", data: sku)
  end

  def update(conn, %{"id" => id, "data" => data = %{"type" => "sku", "attributes" => _sku_params}}) do
    sku = Repo.get!(Sku, id)
    changeset = Sku.changeset(sku, conn.assigns[:locale], Params.to_attributes(data))

    case Repo.update(changeset) do
      {:ok, sku} ->
        sku = translate(sku, conn.assigns[:locale])
        render(conn, "show.json-api", data: sku)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    sku = Repo.get!(Sku, id)

    # Here we use delete! (with a bang) because we expect
    # it to always work (and if it does not, it will raise).
    Repo.delete!(sku)

    send_resp(conn, :no_content, "")
  end

  defp translate(struct, locale) when locale !== "en" do
    t_attributes = Map.new(Map.get(struct.translations, locale, %{}), fn({k, v}) -> { String.to_atom(k), v } end)
    Map.merge(struct, t_attributes)
  end
  defp translate(struct, _locale), do: struct

end
