defmodule BlueJetWeb.EmailTemplateController do
  use BlueJetWeb, :controller

  alias JaSerializer.Params
  alias BlueJet.Notification

  action_fallback BlueJetWeb.FallbackController

  plug :scrub_params, "data" when action in [:create, :update]

  def index(conn = %{ assigns: assigns }, params) do
    request = %AccessRequest{
      vas: assigns[:vas],
      search: params["search"],
      filter: assigns[:filter],
      pagination: %{ size: assigns[:page_size], number: assigns[:page_number] },
      preloads: assigns[:preloads]
    }

    case Notification.list_email_template(request) do
      {:ok, %{ data: email_templates, meta: meta }} ->
        render(conn, "index.json-api", data: email_templates, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

      other -> other
    end
  end

  def create(conn = %{ assigns: assigns }, %{ "data" => data = %{ "type" => "EmailTemplate" } }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      fields: Params.to_attributes(data),
      preloads: assigns[:preloads]
    }

    case Notification.create_email_template(request) do
      {:ok, %{ data: email_templates, meta: meta }} ->
        conn
        |> put_status(:created)
        |> render("show.json-api", data: email_templates, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

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

    case Notification.get_email_template(request) do
      {:ok, %{ data: email_template, meta: meta }} ->
        render(conn, "show.json-api", data: email_template, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

      other -> other
    end
  end

  def update(conn = %{ assigns: assigns }, %{ "id" => id, "data" => data = %{ "type" => "EmailTemplate" } }) do
    request = %AccessRequest{
      vas: assigns[:vas],
      params: %{ "id" => id },
      fields: Params.to_attributes(data),
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    case Notification.update_email_template(request) do
      {:ok, %{ data: email_template, meta: meta }} ->
        render(conn, "show.json-api", data: email_template, opts: [meta: camelize_map(meta), include: conn.query_params["include"]])

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

    case Notification.delete_email_template(request) do
      {:ok, _} -> send_resp(conn, :no_content, "")

      other -> other
    end
  end
end
