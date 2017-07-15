defmodule BlueJet.ExternalFileController do
  use BlueJet.Web, :controller

  alias JaSerializer.Params
  alias BlueJet.FileStorage
  alias BlueJet.ExternalFile

  plug :scrub_params, "data" when action in [:create, :update]

  def index(conn = %{ assigns: assigns = %{ vas: %{ account_id: _ } }, query_params: query_params }, params) do
    request = %{
      vas: assigns[:vas],
      search_keyword: params["search"],
      filter: assigns[:filter],
      page_size: assigns[:page_size],
      page_number: assigns[:page_number],
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    %{ external_files: external_files, total_count: total_count, result_count: result_count } = FileStorage.list_external_files(request)

    meta = %{
      totalCount: total_count,
      resultCount: result_count
    }

    render(conn, "index.json-api", data: external_files, opts: [meta: meta, include: query_params["include"]])
  end

  def create(conn = %{ assigns: assigns = %{ vas: vas } }, %{ "data" => data = %{ "type" => "ExternalFile" } }) when map_size(vas) == 2 do
    request = %{
      vas: assigns[:vas],
      fields: Params.to_attributes(data),
      preloads: assigns[:preloads]
    }

    case FileStorage.create_external_file(request) do
      {:ok, external_file} ->
        conn
        |> put_status(:created)
        |> render("show.json-api", data: external_file, opts: [include: conn.query_params["include"]])
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: extract_errors(changeset))
    end
  end

  def show(conn = %{ assigns: assigns = %{ vas: %{ account_id: _ } } }, %{ "id" => ef_id }) do
    request = %{
      vas: assigns[:vas],
      external_file_id: ef_id,
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    external_file = FileStorage.get_external_file!(request)

    render(conn, "show.json-api", data: external_file)
  end

  def update(conn = %{ assigns: assigns = %{ vas: vas } }, %{ "id" => ef_id, "data" => data = %{ "type" => "ExternalFile" } }) when map_size(vas) == 2 do
    request = %{
      vas: assigns[:vas],
      external_file_id: ef_id,
      fields: Params.to_attributes(data),
      preloads: assigns[:preloads],
      locale: assigns[:locale]
    }

    case FileStorage.update_external_file(request) do
      {:ok, external_file} ->
        render(conn, "show.json-api", data: external_file, opts: [include: conn.query_params["include"]])
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:errors, data: extract_errors(changeset))
    end
  end

  def delete(%{ assigns: %{ vas: %{ account_id: account_id, user_id: _ } } } = conn, %{"id" => id}) do
    external_file = ExternalFile |> Repo.get_by!(account_id: account_id, id: id)

    external_file
    |> ExternalFile.delete_object
    |> Repo.delete!

    send_resp(conn, :no_content, "")
  end
end
