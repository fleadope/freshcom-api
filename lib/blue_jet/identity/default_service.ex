defmodule BlueJet.Identity.DefaultService do
  use BlueJet, :service
  use BlueJet.EventEmitter, namespace: :identity

  alias Ecto.{Multi, Changeset}
  alias BlueJet.Identity.{Account, User, Password, AccountMembership, RefreshToken, PhoneVerificationCode}

  @behaviour BlueJet.Identity.Service

  #
  # MARK: Account
  #
  def get_account(%{ account_id: nil }), do: nil
  def get_account(%{ account_id: account_id, account: nil }), do: get_account(account_id)
  def get_account(%{ account: account }) when not is_nil(account), do: account
  def get_account(%{ account_id: account_id }), do: get_account(account_id)
  def get_account(map) when is_map(map), do: nil
  def get_account(id), do: Repo.get!(Account, id)

  defp get_account_id(opts) do
    cond do
      opts[:account_id] -> opts[:account_id]
      opts[:account] -> opts[:account].id
      true -> nil
    end
  end

  defp put_account(opts) do
    %{ opts | account: get_account(opts) }
  end

  def create_account(fields) do
    changeset =
      %Account{ mode: "live" }
      |> Account.changeset(:insert, fields)

    statements =
      Multi.new()
      |> Multi.insert(:account, changeset)
      |> Multi.run(:test_account, fn(%{ account: account }) ->
          %Account{ live_account_id: account.id, mode: "test" }
          |> Account.changeset(:insert, fields)
          |> Repo.insert()
         end)
      |> Multi.run(:prt_live, fn(%{ account: account }) ->
          prt_live = Repo.insert!(%RefreshToken{ account_id: account.id })
          {:ok, prt_live}
         end)
      |> Multi.run(:prt_test, fn(%{ test_account: test_account }) ->
          prt_test = Repo.insert!(%RefreshToken{ account_id: test_account.id })
          {:ok, prt_test}
         end)
      |> Multi.run(:after_account_create, fn(%{ account: account, test_account: test_account }) ->
          emit_event("identity.account.create.success", %{ account: account, test_account: test_account })
         end)

    case Repo.transaction(statements) do
      {:ok, %{ account: account, test_account: test_account }} ->
        account = %{ account | test_account_id: test_account.id, test_account: test_account }
        {:ok, account}

      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def update_account(account = %Account{}, fields, opts \\ %{}) do
    changeset = Account.changeset(account, :update, fields, opts[:locale])

    statements =
      Multi.new()
      |> Multi.update(:account, changeset)
      |> Multi.run(:processed_account, fn(%{ account: account }) ->
          Account.process(account, changeset)
         end)

    case Repo.transaction(statements) do
      {:ok, %{ processed_account: account }} ->
        {:ok, account}

      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  #
  # MARK: User
  #
  def create_user(fields, %{ account: nil }) do
    account_fields =
      fields
      |> Map.take(["default_locale"])
      |> Map.put("name", fields["account_name"])

    statements =
      Multi.new()
      |> Multi.run(:account, fn(_) ->
          create_account(account_fields)
         end)
      |> Multi.run(:user, fn(%{ account: account }) ->
          %User{ default_account_id: account.id, email_verification_token: User.generate_email_verification_token() }
          |> User.changeset(:insert, fields)
          |> Repo.insert()
         end)
      |> Multi.run(:account_membership, fn(%{ account: account, user: user }) ->
          account_membership = Repo.insert!(%AccountMembership{
            account_id: account.id,
            user_id: user.id,
            role: "administrator"
          })

          {:ok, account_membership}
         end)
      |> Multi.run(:urt_live, fn(%{ account: account, user: user}) ->
          refresh_token = Repo.insert!(%RefreshToken{ account_id: account.id, user_id: user.id })
          {:ok, refresh_token}
         end)
      |> Multi.run(:urt_test, fn(%{ account: account, user: user}) ->
          refresh_token = Repo.insert!(%RefreshToken{ account_id: account.test_account_id, user_id: user.id })
          {:ok, refresh_token}
         end)
      |> Multi.run(:after_create, fn(%{ user: user }) ->
          emit_event("identity.user.create.success", %{ user: user, account: nil })
          emit_event("identity.email_verification_token.create.success", %{ user: user, account: nil })
         end)

    case Repo.transaction(statements) do
      {:ok, %{ user: user, account: account }} ->
        user = %{ user | default_account: account }
        {:ok, user}

      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def create_user(fields, %{ account: account }) do
    test_account = Repo.get_by(Account, mode: "test", live_account_id: account.id)

    live_account_id = if test_account do
      account.id
    else
      nil
    end
    test_account_id = if test_account do
      test_account.id
    else
      account.id
    end

    user = %User{
      account_id: account.id,
      account: account,
      default_account_id: account.id,
      default_account: account,
      email_verification_token: User.generate_email_verification_token()
    }
    changeset =
      user
      |> User.changeset(:insert, fields)

    statements =
      Multi.new()
      |> Multi.insert(:user, changeset)
      |> Multi.run(:account_membership, fn(%{ user: user }) ->
          Repo.insert(%AccountMembership{
            account_id: account.id,
            user_id: user.id,
            role: Map.get(fields, "role")
          })
         end)
      |> Multi.run(:urt_live, fn(%{ user: user }) ->
          if live_account_id do
            refresh_token = Repo.insert!(%RefreshToken{ account_id: live_account_id, user_id: user.id })
            {:ok, refresh_token}
          else
            {:ok, nil}
          end
         end)
      |> Multi.run(:urt_test, fn(%{ user: user }) ->
          if test_account_id do
            refresh_token = Repo.insert!(%RefreshToken{ account_id: test_account_id, user_id: user.id })
            {:ok, refresh_token}
          else
            {:ok, nil}
          end
         end)
      |> Multi.run(:processed_user, fn(%{ user: user }) ->
          User.process(user, changeset)
         end)
      |> Multi.run(:after_create, fn(%{ user: user }) ->
          emit_event("identity.user.create.success", %{ user: user, account: account })

          if user.email do
            emit_event("identity.email_verification_token.create.success", %{ user: user, account: account })
          end

          {:ok, nil}
         end)

    case Repo.transaction(statements) do
      {:ok, %{ user: user }} -> {:ok, user}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def create_user(fields, opts) do
    opts = put_account(opts)
    create_user(fields, opts)
  end

  def update_user(nil, _, _), do: {:error, :not_found}

  def update_user(user = %User{}, fields, opts) do
    account = get_account(opts)
    preloads = get_preloads(opts, account)

    changeset =
      %{ user | account: account }
      |> User.changeset(:update, fields)

    statements =
      Multi.new()
      |> Multi.update(:user, changeset)
      |> Multi.run(:processed_user, fn(%{ user: user}) ->
          User.process(user, changeset)
         end)

    case Repo.transaction(statements) do
      {:ok, %{ processed_user: user }} ->
        user = preload(user, preloads[:path], preloads[:opts])
        {:ok, user}

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  def update_user(id, fields, opts) do
    opts = put_account(opts)
    account = opts[:account]

    User
    |> Repo.get_by(id: id, account_id: account.id)
    |> update_user(fields, opts)
  end

  def get_user(fields, opts) do
    account_id = get_account_id(opts)

    User.Query.default()
    |> User.Query.for_account(account_id)
    |> Repo.get_by(fields)
  end

  def delete_user(nil, _), do: {:error, :not_found}

  def delete_user(user = %User{}, opts) do
    account = get_account(opts)

    changeset =
      %{ user | account: account }
      |> User.changeset(:delete)

    with {:ok, user} <- Repo.delete(changeset) do
      {:ok, user}
    else
      other -> other
    end
  end

  def delete_user(id, opts) do
    opts = put_account(opts)
    account = opts[:account]

    User
    |> Repo.get_by(id: id, account_id: account.id)
    |> delete_user(opts)
  end

  #
  # MARK: Email Verification Token
  #
  def create_email_verification_token(nil), do: {:error, :not_found}

  def create_email_verification_token(user = %User{}) do
    account = user.account || get_account(user)

    statements =
      Multi.new()
      |> Multi.run(:user, fn(_) ->
          user = User.refresh_email_verification_token(user)
          {:ok, user}
         end)
      |> Multi.run(:after_create, fn(%{ user: user }) ->
          emit_event("identity.email_verification_token.create.success", %{ user: user, account: account })
         end)

    case Repo.transaction(statements) do
      {:ok, %{ user: user }} -> {:ok, user}

      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def create_email_verification_token(%{ "email" => nil }, _), do: {:error, :not_found}

  def create_email_verification_token(%{ "email" => email }, opts) do
    user = get_user(%{ email: email }, opts)

    if user do
      %{ user | account: opts[:account] }
      |> create_email_verification_token()
    else
      {:error, :not_found}
    end
  end

  #
  # MARK: Email Verification
  #
  def create_email_verification(nil), do: {:error, :not_found}

  def create_email_verification(user = %{}) do
    User.verify_email(user)
    {:ok, user}
  end

  def create_email_verification(%{ "token" => nil }, _), do: {:error, :not_found}

  def create_email_verification(%{ "token" => token }, opts = %{ account: nil }) when map_size(opts) == 1 do
    User.Query.default()
    |> User.Query.global()
    |> Repo.get_by(email_verification_token: token)
    |> create_email_verification()
  end

  def create_email_verification(%{ "token" => token }, opts = %{ account: account }) when map_size(opts) == 1 do
    User.Query.default()
    |> User.Query.for_account(account.id)
    |> Repo.get_by(email_verification_token: token)
    |> create_email_verification()
  end

  def create_email_verification(_, _), do: {:error, :not_found}

  #
  # MARK: Password Reset Token
  #

  @doc """
  When an account is provided in `opts`, this function will only search for account
  user otherwise this function will only search for global user.
  """
  def create_password_reset_token(%{ "email" => email }, opts) do
    changeset =
      Changeset.change(%User{}, %{ email: email })
      |> Changeset.validate_required(:email)
      |> Changeset.validate_format(:email, Application.get_env(:blue_jet, :email_regex))

    with true <- changeset.valid?,
         user = %User{} <- get_user(%{ email: email }, opts)
    do
      user = User.refresh_password_reset_token(user)
      event_data = Map.merge(opts, %{ user: user })
      emit_event("identity.password_reset_token.create.success", event_data)

      {:ok, user}
    else
      false ->
        {:error, changeset}

      nil ->
        event_data = Map.merge(opts, %{ email: email })
        emit_event("identity.password_reset_token.create.error.email_not_found", event_data)
        {:error, :not_found}
    end
  end

  #
  # MARK: Password
  #

  # TODO: rename to update_password instead
  def update_password(password = %Password{}, new_password) do
    changeset =
      password
      |> Password.changeset(:update, %{ value: new_password })

    case Repo.update(changeset) do
      {:ok, password} ->
        {:ok, password}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_password(nil, _, _), do: {:error, :not_found}

  def update_password(%{ "reset_token" => reset_token }, new_password, opts = %{ account: nil }) when map_size(opts) == 1 do
    password =
      Password.Query.default()
      |> Password.Query.global()
      |> Repo.get_by(reset_token: reset_token)

    if password do
      update_password(password, new_password)
    else
      {:error, :not_found}
    end
  end

  def update_password(%{ "reset_token" => reset_token }, new_password, opts = %{ account: account }) when map_size(opts) == 1 do
    password =
      Password.Query.default()
      |> Password.Query.for_account(account.id)
      |> Repo.get_by(reset_token: reset_token)

    if password do
      update_password(password, new_password)
    else
      {:error, :not_found}
    end
  end

  #
  # MARK: Phone Verification Code
  #
  def create_phone_verification_code(fields, opts) do
    account = get_account(opts)

    changeset =
      %PhoneVerificationCode{ account_id: account.id, account: account }
      |> PhoneVerificationCode.changeset(:insert, fields)

    statements =
      Multi.new()
      |> Multi.insert(:pvc, changeset)
      |> Multi.run(:after_create, fn(%{ pvc: pvc }) ->
          emit_event("identity.phone_verification_code.create.success", %{ phone_verification_code: pvc, account: account })
         end)

    case Repo.transaction(statements) do
      {:ok, %{ pvc: pvc }} ->
        {:ok, pvc}

      {:error, _, changeset, _} -> {:error, changeset}
    end
  end
end