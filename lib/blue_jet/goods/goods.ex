defmodule BlueJet.Goods do
  use BlueJet, :context

  alias BlueJet.Identity
  alias BlueJet.Goods.Stockable
  alias BlueJet.Goods.Unlockable
  alias BlueJet.Goods.Depositable

  ####
  # Stockable
  ####
  defp stockable_response(nil, _), do: {:error, :not_found}

  defp stockable_response(stockable, request = %{ account: account }) do
    preloads = Stockable.Query.preloads(request.preloads, role: request.role)

    stockable =
      stockable
      |> Repo.preload(preloads)
      |> Stockable.put_external_resources(request.preloads, %{ account: account, role: request.role })
      |> Translation.translate(request.locale, account.default_locale)

    {:ok, %AccessResponse{ meta: %{ locale: request.locale }, data: stockable }}
  end

  def list_stockable(request) do
    with {:ok, request} <- preprocess_request(request, "goods.list_stockable") do
      request
      |> AccessRequest.transform_by_role()
      |> do_list_stockable()
    else
      {:error, _} -> {:error, :access_denied}
    end
  end

  def do_list_stockable(request = %{ account: account, filter: filter, counts: counts, pagination: pagination }) do
    data_query =
      Stockable
      |> search([:name, :code, :id], request.search, request.locale, account.default_locale, Stockable.translatable_fields)
      |> filter_by(status: filter[:status])
      |> Stockable.Query.for_account(account.id)

    total_count = Repo.aggregate(data_query, :count, :id)
    all_count =
      Stockable.Query.default()
      |> filter_by(status: counts[:all][:status])
      |> Stockable.Query.for_account(account.id)
      |> Repo.aggregate(:count, :id)

    preloads = Stockable.Query.preloads(request.preloads, role: request.role)
    stockables =
      data_query
      |> paginate(size: pagination[:size], number: pagination[:number])
      |> Repo.all()
      |> Repo.preload(preloads)
      |> Stockable.put_external_resources(request.preloads, %{ account: account, role: request.role })
      |> Translation.translate(request.locale, account.default_locale)

    response = %AccessResponse{
      meta: %{
        locale: request.locale,
        all_count: all_count,
        total_count: total_count
      },
      data: stockables
    }

    {:ok, response}
  end

  def create_stockable(request) do
    with {:ok, request} <- preprocess_request(request, "goods.create_stockable") do
      request
      |> do_create_stockable()
    else
      {:error, _} -> {:error, :access_denied}
    end
  end

  def do_create_stockable(request = %{ account: account }) do
    request = %{ request | locale: account.default_locale }

    fields = Map.merge(request.fields, %{ "account_id" => account.id })
    changeset = Stockable.changeset(%Stockable{}, fields, request.locale)

    with {:ok, stockable} <- Repo.insert(changeset) do
      stockable_response(stockable, request)
    else
      {:error, %{ errors: errors }} ->
        {:error, %AccessResponse{ errors: errors }}

      other -> other
    end
  end

  def get_stockable(request) do
    with {:ok, request} <- preprocess_request(request, "goods.get_stockable") do
      request
      |> do_get_stockable()
    else
      {:error, _} -> {:error, :access_denied}
    end
  end

  def do_get_stockable(request = %{ account: account, params: %{ "id" => id } }) do
    stockable =
      Stockable.Query.default()
      |> Stockable.Query.for_account(account.id)
      |> Repo.get(id)

    stockable_response(stockable, request)
  end

  def update_stockable(request) do
    with {:ok, request} <- preprocess_request(request, "goods.update_stockable") do
      request
      |> do_update_stockable()
    else
      {:error, _} -> {:error, :access_denied}
    end
  end

  def do_update_stockable(request = %{ account: account, params: %{ "id" => id } }) do
    stockable =
      Stockable.Query.default()
      |> Stockable.Query.for_account(account.id)
      |> Repo.get(id)

    with %Stockable{} <- stockable,
         changeset <- Stockable.changeset(stockable, request.fields, request.locale),
         {:ok, stockable} <- Repo.update(changeset)
    do
      stockable_response(stockable, request)
    else
      {:error, %{ errors: errors }} ->
        {:error, %AccessResponse{ errors: errors }}

      nil ->
        {:error, :not_found}
    end
  end

  def delete_stockable(request) do
    with {:ok, request} <- preprocess_request(request, "goods.delete_stockable") do
      request
      |> do_delete_stockable()
    else
      {:error, _} -> {:error, :access_denied}
    end
  end

  def do_delete_stockable(%AccessRequest{ vas: vas, params: %{ "id" => id } }) do
    stockable =
      Stockable.Query.default()
      |> Stockable.Query.for_account(vas[:account_id])
      |> Repo.get(id)

    if stockable do
      Repo.delete!(stockable)
      {:ok, %AccessResponse{}}
    else
      {:error, :not_found}
    end
  end

  ####
  # Unlockable
  ####
  def list_unlockable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.list_unlockable") do
      do_list_unlockable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_list_unlockable(request = %AccessRequest{ vas: %{ account_id: account_id }, filter: filter, pagination: pagination }) do
    query =
      Unlockable
      |> search([:name, :print_name, :code, :id], request.search, request.locale, account_id)
      |> filter_by(status: filter[:status])
      |> Unlockable.Query.for_account(account_id)
    result_count = Repo.aggregate(query, :count, :id)

    total_query = Unlockable |> Unlockable.Query.for_account(account_id)
    total_count = Repo.aggregate(total_query, :count, :id)

    query = paginate(query, size: pagination[:size], number: pagination[:number])

    unlockables =
      Repo.all(query)
      |> Repo.preload(request.preloads)
      |> Translation.translate(request.locale)

    response = %AccessResponse{
      meta: %{
        total_count: total_count,
        result_count: result_count,
      },
      data: unlockables
    }

    {:ok, response}
  end

  def create_unlockable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.create_unlockable") do
      do_create_unlockable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_create_unlockable(request = %AccessRequest{ vas: vas }) do
    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id] })
    changeset = Unlockable.changeset(%Unlockable{}, fields)

    with {:ok, unlockable} <- Repo.insert(changeset) do
      unlockable = Repo.preload(unlockable, Unlockable.Query.preloads(request.preloads))
      {:ok, %AccessResponse{ data: unlockable }}
    else
      {:error, %{ errors: errors }} ->
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def get_unlockable(request) do
    with {:ok, request} <- preprocess_request(request, "goods.get_unlockable") do
      request
      |> do_get_unlockable()
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_get_unlockable(request = %AccessRequest{ account: account, params: %{ "id" => id } }) do
    unlockable = Unlockable |> Unlockable.Query.for_account(account.id) |> Repo.get(id)
    do_get_unlockable_response(unlockable, request)
  end
  def do_get_unlockable(request = %AccessRequest{ account: account, params: %{ "code" => code } }) do
    unlockable = Unlockable |> Unlockable.Query.for_account(account.id) |> Repo.get_by(code: code)
    do_get_unlockable_response(unlockable, request)
  end
  def do_get_unlockable_response(nil, _), do: {:error, :not_found}
  def do_get_unlockable_response(unlockable, request) do
    unlockable =
      unlockable
      |> Repo.preload(Unlockable.Query.preloads(request.preloads))
      |> Unlockable.put_external_resources(request.preloads)
      |> Translation.translate(request.locale)

    {:ok, %AccessResponse{ data: unlockable }}
  end

  def update_unlockable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.update_unlockable") do
      do_update_unlockable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_update_unlockable(request = %{ vas: vas, params: %{ "id" => id }}) do
    unlockable = Unlockable |> Unlockable.Query.for_account(vas[:account_id]) |> Repo.get(id)

    with %Unlockable{} <- unlockable,
         changeset <- Unlockable.changeset(unlockable, request.fields, request.locale),
        {:ok, unlockable} <- Repo.update(changeset)
    do
      unlockable =
        unlockable
        |> Repo.preload(Unlockable.Query.preloads(request.preloads))
        |> Translation.translate(request.locale)

      {:ok, %AccessResponse{ data: unlockable }}
    else
      nil -> {:error, :not_found}
      {:error, %{ errors: errors }} ->
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def delete_unlockable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.delete_unlockable") do
      do_delete_unlockable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_delete_unlockable(%AccessRequest{ vas: vas, params: %{ "id" => id } }) do
    unlockable = Unlockable |> Unlockable.Query.for_account(vas[:account_id]) |> Repo.get!(id)
    if unlockable do
      Repo.delete!(unlockable)
      {:ok, %AccessResponse{}}
    else
      {:error, :not_found}
    end
  end

  ####
  # Point Deposit
  ####
  def list_depositable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.list_depositable") do
      do_list_depositable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_list_depositable(request = %AccessRequest{ vas: %{ account_id: account_id }, filter: filter, pagination: pagination }) do
    query =
      Depositable
      |> search([:name, :print_name, :code, :id], request.search, request.locale, account_id)
      |> filter_by(status: filter[:status])
      |> Depositable.Query.for_account(account_id)
    result_count = Repo.aggregate(query, :count, :id)

    total_query = Depositable |> Depositable.Query.for_account(account_id)
    total_count = Repo.aggregate(total_query, :count, :id)

    query = paginate(query, size: pagination[:size], number: pagination[:number])

    depositables =
      Repo.all(query)
      |> Repo.preload(request.preloads)
      |> Translation.translate(request.locale)

    response = %AccessResponse{
      meta: %{
        total_count: total_count,
        result_count: result_count,
      },
      data: depositables
    }

    {:ok, response}
  end

  def create_depositable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.create_depositable") do
      do_create_depositable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_create_depositable(request = %AccessRequest{ vas: vas }) do
    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id] })
    changeset = Depositable.changeset(%Depositable{}, fields)

    with {:ok, depositable} <- Repo.insert(changeset) do
      depositable = Repo.preload(depositable, Depositable.Query.preloads(request.preloads))
      {:ok, %AccessResponse{ data: depositable }}
    else
      {:error, %{ errors: errors }} ->
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def get_depositable(request) do
    with {:ok, request} <- preprocess_request(request, "goods.get_depositable") do
      request
      |> do_get_depositable()
    else
      {:error, _} -> {:error, :access_denied}
    end
  end

  def do_get_depositable(request = %{ account: account, params: %{ "id" => id } }) do
    depositable =
      Depositable.Query.default()
      |> Depositable.Query.for_account(account.id)
      |> Repo.get(id)

    if depositable do
      depositable =
        depositable
        |> Repo.preload(Depositable.Query.preloads(request.preloads))
        |> Depositable.put_external_resources(request.preloads)
        |> Translation.translate(request.locale)

      {:ok, %AccessResponse{ data: depositable }}
    else
      {:error, :not_found}
    end
  end

  def update_depositable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.update_depositable") do
      do_update_depositable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_update_depositable(request = %{ vas: vas, params: %{ "id" => id }}) do
    depositable = Depositable |> Depositable.Query.for_account(vas[:account_id]) |> Repo.get(id)

    with %Depositable{} <- depositable,
         changeset <- Depositable.changeset(depositable, request.fields, request.locale),
        {:ok, depositable} <- Repo.update(changeset)
    do
      depositable =
        depositable
        |> Repo.preload(Depositable.Query.preloads(request.preloads))
        |> Translation.translate(request.locale)

      {:ok, %AccessResponse{ data: depositable }}
    else
      nil -> {:error, :not_found}
      {:error, %{ errors: errors }} ->
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def delete_depositable(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "inventory.delete_depositable") do
      do_delete_depositable(%{ request | role: role })
    else
      {:error, _} -> {:error, :access_denied}
    end
  end
  def do_delete_depositable(%AccessRequest{ vas: vas, params: %{ "id" => id } }) do
    depositable = Depositable |> Depositable.Query.for_account(vas[:account_id]) |> Repo.get!(id)
    if depositable do
      Repo.delete!(depositable)
      {:ok, %AccessResponse{}}
    else
      {:error, :not_found}
    end
  end
end