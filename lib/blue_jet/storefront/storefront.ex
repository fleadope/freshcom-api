defmodule BlueJet.Storefront do
  use BlueJet, :context

  alias Ecto.Changeset

  alias BlueJet.Identity

  alias BlueJet.Identity.Customer
  alias BlueJet.Storefront.Order
  alias BlueJet.Storefront.OrderLineItem
  alias BlueJet.Storefront.Payment
  alias BlueJet.Storefront.StripePaymentError
  alias BlueJet.Storefront.Unlock
  alias BlueJet.Storefront.Refund
  alias BlueJet.Storefront.Card

  alias BlueJet.FileStorage.ExternalFile

  ####
  # Order
  ####
  def list_order(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.list_order") do
      do_list_order(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_list_order(request = %AccessRequest{ vas: %{ account_id: account_id }, filter: filter, pagination: pagination }) do
    filter = if !filter[:status] do
      Map.put(filter, :status, "opened")
    else
      filter
    end

    query =
      Order.Query.default()
      |> search([:first_name, :last_name, :code, :email, :phone_number, :id], request.search, request.locale)
      |> filter_by(
        status: filter[:status],
        label: filter[:label],
        delivery_address_province: filter[:delivery_address_province],
        delivery_address_city: filter[:delivery_address_city],
        fulfillment_method: filter[:fulfillment_method]
      )
      |> Order.Query.for_account(account_id)
    result_count = Repo.aggregate(query, :count, :id)

    total_query = Order.Query.default() |> Order.Query.for_account(account_id)
    total_count = Repo.aggregate(total_query, :count, :id)

    query = paginate(query, size: pagination[:size], number: pagination[:number])

    orders =
      Repo.all(query)
      |> Repo.preload(Order.Query.preloads(request.preloads))
      |> Translation.translate(request.locale)

    response = %AccessResponse{
      meta: %{
        total_count: total_count,
        result_count: result_count,
      },
      data: orders
    }

    {:ok, response}
  end

  def create_order(request = %{ vas: vas }) do
    defaults = %{ preloads: [], fields: %{} }
    request = Map.merge(defaults, request)

    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id], "customer_id" => vas[:customer_id] || request.fields["customer_id"] })
    changeset = Order.changeset(%Order{}, fields)

    with {:ok, order} <- Repo.insert(changeset) do
      order = Repo.preload(order, request.preloads)
      {:ok, order}
    else
      other -> other
    end
  end

  def get_order!(request = %{ vas: vas, order_id: order_id }) do
    defaults = %{ locale: "en", preloads: [] }
    request = Map.merge(defaults, request)

    order_scope =
      case vas[:customer_id] do
        nil -> Order
        customer_id -> from(o in Order, where: o.customer_id == ^customer_id)
      end

    order =
      order_scope
      |> Repo.get_by!(account_id: vas[:account_id], id: order_id)
      |> Order.preload(request.preloads)
      |> Translation.translate(request.locale)

    order
  end

  def update_order(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.update_order") do
      do_update_order(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_update_order(request = %AccessRequest{ vas: vas, params: %{ order_id: order_id }}) do
    order = Order |> Order.Query.for_account(vas[:account_id]) |> Repo.get(order_id)
    changeset = Order.changeset(order, request.fields, request.locale)

    with %Order{} <- order,
         changeset <- Order.changeset(order, request.fields, request.locale),
          {:ok, order} <- Repo.update(changeset)
    do
      order =
        order
        |> Repo.preload(Order.Query.preloads(request.preloads))
        |> Translation.translate(request.locale)

      {:ok, %AccessResponse{ data: order }}
    else
      {:error, changeset} ->
        errors = Enum.into(changeset.errors, %{})
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def delete_order!(%{ vas: vas, order_id: order_id }) do
    order = Repo.get_by!(Order, account_id: vas[:account_id], id: order_id)
    Repo.delete!(order)
  end

  ####
  # Order Line Item
  ####
  def create_order_line_item(request = %{ vas: vas }) do
    defaults = %{ preloads: [], fields: %{} }
    request = Map.merge(defaults, request)

    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id] })

    with changeset = %{valid?: true} <- OrderLineItem.changeset(%OrderLineItem{}, fields) do
      order = Repo.get!(Order, Changeset.get_field(changeset, :order_id))
      Repo.transaction(fn ->
        order_line_item = Repo.insert!(changeset)
        OrderLineItem.balance!(order_line_item)
        Order.balance!(order)
        order_line_item
      end)
    else
      other -> {:error, other}
    end
  end

  def update_order_line_item(request = %{ vas: vas, order_line_item_id: order_line_item_id }) do
    defaults = %{ preloads: [], fields: %{} }
    request = Map.merge(defaults, request)

    order_line_item = Repo.get_by!(OrderLineItem, account_id: vas[:account_id], id: order_line_item_id) |> Repo.preload(:order)

    with changeset = %{valid?: true} <- OrderLineItem.changeset(order_line_item, request.fields) do
      Repo.transaction(fn ->
        order_line_item = Repo.update!(changeset)
        OrderLineItem.balance!(order_line_item)
        Order.balance!(order_line_item.order)
        order_line_item
      end)
    else
      other -> {:error, other}
    end
  end

  def delete_order_line_item!(request = %{ vas: vas, order_line_item_id: order_line_item_id }) do
    defaults = %{ preloads: [], fields: %{} }
    request = Map.merge(defaults, request)

    order_line_item = Repo.get_by!(OrderLineItem, account_id: vas[:account_id], id: order_line_item_id)
    order = Repo.get_by!(Order, account_id: vas[:account_id], id: order_line_item.order_id)

    Repo.transaction(fn ->
      Repo.delete!(order_line_item)
      Order.balance!(order)
    end)
  end

  def handle_event("billing.payment.before_create", %{ fields: fields, owner: %{ type: "Customer", id: customer_id } }) do
    customer = Repo.get!(Customer, customer_id)
    customer = Customer.preprocess(customer, payment_processor: "stripe")
    xxx = Map.put(fields, "stripe_customer_id", customer.stripe_customer_id)
    {:ok, xxx}
  end
  def handle_event("billing.payment.created", %{ payment: %{ target_type: "Order", target_id: order_id } }) do
    order = Repo.get!(Order, order_id)
    order_changeset = Changeset.change(order, status: "opened")

    order = Repo.update!(order_changeset)
    Order.process(order, order_changeset)
  end
  def handle_event(_, data) do
    {:ok, nil}
  end

  # def list_cards(request = %{ vas: vas, customer_id: target_customer_id }) do
  #   defaults = %{ preloads: [], fields: %{} }
  #   request = Map.merge(defaults, request)
  #   customer_id = vas[:customer_id] || target_customer_id
  #   account_id = vas[:account_id]

  #   query =
  #     Card
  #     |> filter_by(status: "saved_by_customer")
  #     |> where([c], c.account_id == ^account_id)
  #     |> where([c], c.customer_id == ^customer_id)

  #   result_count = Repo.aggregate(query, :count, :id)

  #   total_query = Card |> where([s], s.account_id == ^account_id)
  #   total_count = Repo.aggregate(total_query, :count, :id)

  #   query = paginate(query, size: request.page_size, number: request.page_number)

  #   cards =
  #     Repo.all(query)
  #     |> Translation.translate(request.locale)

  #   %{
  #     total_count: total_count,
  #     result_count: result_count,
  #     cards: cards
  #   }
  # end

  ####
  # Payment
  ####

  # def get_payment!(request = %{ vas: vas, payment_id: payment_id }) do
  #   defaults = %{ locale: "en", preloads: [] }
  #   request = Map.merge(defaults, request)

  #   payment =
  #     Payment
  #     |> Repo.get_by!(account_id: vas[:account_id], id: payment_id)
  #     |> Payment.preload(request.preloads)
  #     |> Translation.translate(request.locale)

  #   payment
  # end

  # def create_payment(request = %{ vas: vas }) do
  #   defaults = %{ preloads: [], fields: %{} }
  #   request = Map.merge(defaults, request)
  #   fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id] })
  #   changeset = Payment.changeset(%Payment{}, fields)

  #   # TODO: remove options
  #   order =
  #     Order
  #     |> Repo.get_by!(account_id: vas[:account_id], id: request.fields["order_id"])
  #     |> Repo.preload(:customer)

  #   Customer.preprocess(order.customer, payment_processor: request.fields["processor"])

  #   # TODO: handle stock and shipping errors
  #   create_payment(changeset)
  # end
  # def create_payment(changeset = %Changeset{ valid?: true }) do
  #   # We create the charge first so that stripe_charge can have a reference to the charge,
  #   # since stripe_charge can't be rolled back this avoid an orphan stripe_charge
  #   # so we need to make sure what the stripe_charge is for and refund manually if needed
  #   Repo.transaction(fn ->
  #     payment = Repo.insert!(changeset) |> Repo.preload(:order)

  #     order_changeset = Changeset.change(payment.order, status: "opened")
  #     order = Repo.update!(order_changeset)

  #     with {:ok, _} <- Order.lock_stock(payment.order_id),
  #          {:ok, _} <- Order.lock_shipping_date(payment.order_id),
  #          {:ok, payment} <- Payment.process(payment, changeset),
  #          {:ok, order} <- Order.process(order, order_changeset)
  #     do
  #       payment
  #     else
  #       {:error, errors} -> Repo.rollback(errors)
  #     end
  #   end)
  # end
  # def create_payment(changeset, _) do
  #   {:error, changeset.errors}
  # end

  # def update_payment(request = %{ vas: vas, payment_id: payment_id }) do
  #   defaults = %{ preloads: [], fields: %{} }
  #   request = Map.merge(defaults, request)
  #   payment = Repo.get_by!(Payment, account_id: vas[:account_id], id: payment_id)
  #   update_payment(Payment.changeset(payment, request.fields), request.fields)
  # end
  # def update_payment(changeset = %Changeset{ valid?: true }, options) do
  #   Repo.transaction(fn ->
  #     payment = Repo.update!(changeset)
  #     with {:ok, payment} <- Payment.process(payment, changeset) do
  #       payment
  #     else
  #       {:error, errors} -> Repo.rollback(errors)
  #     end
  #   end)
  # end
  # def update_payment(changeset, _) do
  #   {:error, changeset.errors}
  # end

  # defp format_stripe_errors(stripe_errors) do
  #   [source: { stripe_errors["error"]["message"], [code: stripe_errors["error"]["code"], full_error_message: true] }]
  # end

  # def delete_payment!(request = %{ vas: vas, payment_id: payment_id }) do
  #   payment = Repo.get_by!(Payment, account_id: vas[:account_id], id: payment_id)
  #   Repo.delete!(payment)
  # end

  # ######
  # # Refund
  # ######
  # def create_refund(request = %{ vas: vas }) do
  #   defaults = %{ preloads: [], fields: %{} }
  #   request = Map.merge(defaults, request)
  #   fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id] })

  #   with changeset = %Changeset{ valid?: true } <- Refund.changeset(%Refund{}, fields),
  #     {:ok, refund} <- Repo.transaction(fn ->

  #       refund = Repo.insert!(changeset) |> Repo.preload(:payment)
  #       new_refunded_amount_cents = refund.payment.refunded_amount_cents + refund.amount_cents
  #       new_payment_status = if new_refunded_amount_cents >= refund.payment.paid_amount_cents do
  #         "refunded"
  #       else
  #         "partially_refunded"
  #       end

  #       payment_changeset = Changeset.change(refund.payment, %{ refunded_amount_cents: new_refunded_amount_cents, status: new_payment_status })
  #       payment = Repo.update!(payment_changeset)

  #       with {:ok, refund} <- process_refund(refund, payment) do
  #         refund
  #       else
  #         {:error, errors} -> Repo.rollback(errors)
  #       end

  #     end)
  #   do
  #     {:ok, refund}
  #   else
  #     {:error, changeset = %Changeset{}} -> {:error, changeset.errors}
  #     changeset = %Changeset{} -> {:error, changeset.errors}
  #     other -> other
  #   end
  # end

  # defp process_refund(refund, payment = %Payment{ gateway: "online", processor: "stripe" }) do
  #   with {:ok, stripe_refund} <- create_stripe_refund(refund, payment) do
  #     {:ok, refund}
  #   else
  #     {:error, stripe_errors} -> {:error, format_stripe_errors(stripe_errors)}
  #   end
  # end
  # defp process_refund(refund, _), do: {:ok, refund}

  # defp create_stripe_refund(refund, payment) do
  #   StripeClient.post("/refunds", %{ charge: payment.stripe_charge_id, amount: refund.amount_cents, metadata: %{ fc_refund_id: refund.id }  })
  # end




  ####
  # Customer
  ####
  def create_customer(request = %AccessRequest{ vas: vas }) do
    with {:ok, role} <- Identity.authorize(vas, "storefront.create_customer") do
      do_create_customer(request)
    else
      {:error, reason} -> {:error, :access_denied}
    end
  end
  def do_create_customer(request = %{ vas: vas }) do
    fields = Map.merge(request.fields, %{ "account_id" => vas[:account_id] })
    changeset = Customer.changeset(%Customer{}, fields)

    with {:ok, customer} <- Repo.insert(changeset) do
      customer = Repo.preload(customer, Customer.Query.preloads(request.preloads))
      {:ok, %AccessResponse{ data: customer }}
    else
      {:error, changeset} ->
        errors = Enum.into(changeset.errors, %{})
        {:error, %AccessResponse{ errors: errors }}
    end
  end

  def get_customer!(request = %{ vas: vas, customer_id: customer_id }) do
    defaults = %{ locale: "en", preloads: [] }
    request = Map.merge(defaults, request)

    customer =
      Customer
      |> Repo.get_by!(account_id: vas[:account_id], id: customer_id)
      |> Customer.preload(request.preloads)
      |> Translation.translate(request.locale)

    customer
  end

  def update_customer(request = %{ vas: vas, customer_id: customer_id }) do
    defaults = %{ preloads: [], fields: %{}, locale: "en" }
    request = Map.merge(defaults, request)

    vas_customer_id = vas[:customer_id]

    customer_scope = if vas_customer_id do
      from(c in Customer, where: c.id == ^vas_customer_id)
    else
      Customer
    end
    customer = Repo.get_by!(customer_scope, account_id: vas[:account_id], id: customer_id)

    changeset = Customer.changeset(customer, request.fields, request.locale)

    with {:ok, customer} <- Repo.update(changeset) do
      customer =
        customer
        |> Repo.preload(request.preloads)
        |> Translation.translate(request.locale)

      {:ok, customer}
    else
      other -> other
    end
  end

  def list_customers(request = %{ vas: vas }) do
    defaults = %{ search_keyword: "", filter: %{}, page_size: 25, page_number: 1, locale: "en", preloads: [] }
    request = Map.merge(defaults, request)
    account_id = vas[:account_id]

    query =
      Customer
      |> search([:first_name, :last_name, :code, :email, :phone_number, :id], request.search_keyword, request.locale)
      |> filter_by(status: request.filter[:status], label: request.filter[:label], delivery_address_country_code: request.filter[:delivery_address_country_code])
      |> where([s], s.account_id == ^account_id)
    result_count = Repo.aggregate(query, :count, :id)

    total_query = Customer |> where([s], s.account_id == ^account_id)
    total_count = Repo.aggregate(total_query, :count, :id)

    query = paginate(query, size: request.page_size, number: request.page_number)

    customers =
      Repo.all(query)
      |> Repo.preload(request.preloads)
      |> Translation.translate(request.locale)

    %{
      total_count: total_count,
      result_count: result_count,
      customers: customers
    }
  end

  def delete_customer!(%{ vas: vas, customer_id: customer_id }) do
    customer = Repo.get_by!(Customer, account_id: vas[:account_id], id: customer_id)
    Repo.delete!(customer)
  end
end
