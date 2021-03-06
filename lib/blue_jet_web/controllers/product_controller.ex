defmodule BlueJetWeb.ProductController do
  use BlueJetWeb, :controller

  alias JaSerializer.Params
  alias BlueJet.Catalogue

  action_fallback BlueJetWeb.FallbackController

  plug :scrub_params, "data" when action in [:create, :update]

  def index(conn = %{ assigns: assigns }, params) do
    request = %AccessRequest{
      vas: assigns[:vas],
      search: params["search"],
      filter: assigns[:filter],
      pagination: %{ size: assigns[:page_size], number: assigns[:page_number] },
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    case Catalogue.list_product(request) do
      {:ok, %{ data: products, meta: meta }} ->
        render(conn, "index.json-api", data: products, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

      other -> other
    end
  end

  def create(conn = %{ assigns: assigns }, %{ "data" => data = %{ "type" => "Product" } }) do
    fields =
      Params.to_attributes(data)
      |> underscore_value(["kind", "name_sync"])

    request = %AccessRequest{
      vas: assigns[:vas],
      fields: fields,
      preloads: assigns[:preloads]
    }

    case Catalogue.create_product(request) do
      {:ok, %{ data: product, meta: meta }} ->
        conn
        |> put_status(:created)
        |> render("show.json-api", data: product, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

      {:error, %{ errors: errors }} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: extract_errors(errors))

      other -> other
    end
  end

  def show(conn = %{ assigns: assigns }, %{ "id" => id }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      params: %{ "id" => id },
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    case Catalogue.get_product(request) do
      {:ok, %{ data: product, meta: meta }} ->
        render(conn, "show.json-api", data: product, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

      other -> other
    end
  end

  def update(conn = %{ assigns: assigns }, %{ "id" => id, "data" => data = %{ "type" => "Product" } }) do
    fields =
      Params.to_attributes(data)
      |> underscore_value(["kind", "name_sync"])

    request = %AccessRequest{
      vas: assigns[:vas],
      params: %{ "id" => id },
      fields: fields,
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    case Catalogue.update_product(request) do
      {:ok, %{ data: product, meta: meta }} ->
        render(conn, "show.json-api", data: product, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

      {:error, %{ errors: errors }} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: extract_errors(errors))

      other -> other
    end
  end

  def delete(conn = %{ assigns: assigns }, %{ "id" => id }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      params: %{ "id" => id }
    }

    case Catalogue.delete_product(request) do
      {:ok, _} -> send_resp(conn, :no_content, "")

      other -> other
    end
  end

end
