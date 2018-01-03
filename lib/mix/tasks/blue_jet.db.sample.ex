defmodule Mix.Tasks.BlueJet.Db.Sample do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Add sample data to db"

  @moduledoc """
    This is where we would put any long form documentation or doctests.
  """

  def run(args) do
    # Mix.Tasks.Ecto.Drop.run(args)
    # Mix.Tasks.Ecto.Create.run(args)
    # Mix.Tasks.Ecto.Migrate.run(args)

    alias BlueJet.Repo
    alias BlueJet.Goods.Stockable
    alias BlueJet.Goods.Unlockable
    alias BlueJet.Goods.Depositable
    alias BlueJet.Catalogue.Product
    alias BlueJet.Catalogue.ProductCollection
    alias BlueJet.Catalogue.ProductCollectionMembership
    alias BlueJet.Catalogue.Price
    alias BlueJet.Identity
    alias BlueJet.AccessRequest
    alias BlueJet.CRM

    ensure_started(Repo, [])

    {:ok, %{ data: %{ default_account_id: account1_id } }} = Identity.create_user(%AccessRequest{
      fields: %{
        "first_name" => "Roy",
        "last_name" => "Bao",
        "username" => "user1@example.com",
        "email" => "user1@example.com",
        "password" => "test1234",
        "account_name" => "Outersky",
        "default_locale" => "zh-CN"
      }
    })

    {:ok, %{ data: account1 }} = Identity.get_account(%AccessRequest{
      vas: %{ account_id: account1_id }
    })

    test_account1_id = account1.test_account_id

    {:ok, %{ data: _ }} = CRM.create_customer(%AccessRequest{
      vas: %{ account_id: account1_id },
      fields: %{
        "first_name" => "Tiffany",
        "last_name" => "Wang",
        "email" => "customer1@example.com",
        "status" => "registered",
        "password" => "test1234"
      }
    })

    changeset = ProductCollection.changeset(%ProductCollection{ account_id: test_account1_id }, %{
      "status" => "active",
      "code" => "DEPOSIT",
      "name" => "充值",
      "label" => "deposit"
    })
    deposit_pc = Repo.insert!(changeset)

    changeset = ProductCollection.changeset(%ProductCollection{ account_id: test_account1_id }, %{
      "status" => "active",
      "code" => "TOM",
      "name" => "本月推荐（TOM）",
      "label" => "audio",
      "sort_index" => 300
    })
    Repo.insert!(changeset)

    changeset = ProductCollection.changeset(%ProductCollection{ account_id: test_account1_id }, %{
      "status" => "active",
      "code" => "ASSOC-TR-AUD",
      "name" => "经销商培训CD",
      "label" => "audio",
      "sort_index" => 200
    })
    Repo.insert!(changeset)

    changeset = ProductCollection.changeset(%ProductCollection{ account_id: test_account1_id }, %{
      "status" => "active",
      "code" => "LDR-TR-AUD",
      "name" => "领导力培训CD",
      "label" => "audio",
      "sort_index" => 100
    })
    Repo.insert!(changeset)

    changeset = Depositable.changeset(%Depositable{}, %{
      "account_id" => test_account1_id,
      "code" => "60050",
      "status" => "active",
      "target_type" => "PointAccount",
      "name" => "充值$50",
      "print_name" => "充值$50",
      "amount" => 5000
    })
    deposit_50 = Repo.insert!(changeset)

    changeset = Product.changeset(%Product{}, %{
      "account_id" => test_account1_id,
      "source_id" => deposit_50.id,
      "source_type" => "Depositable",
      "name_sync" => "sync_with_source",
      "maximum_public_order_quantity" => 9999,
      "source_quantity" => 1
    })
    product = Repo.insert!(changeset)

    Repo.insert!(%ProductCollectionMembership{
      account_id: test_account1_id,
      collection_id: deposit_pc.id,
      product_id: product.id,
      sort_index: 100
    })

    changeset = Price.changeset(%Price{}, %{
      "account_id" => test_account1_id,
      "product_id" => product.id,
      "status" => "active",
      "name" => "原价",
      "charge_amount_cents" => 5000,
      "charge_unit" => "EA",
      "order_unit" => "EA"
    })
    Repo.insert!(changeset)

    changeset = Product.changeset(product, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    #######
    changeset = Depositable.changeset(%Depositable{}, %{
      "account_id" => test_account1_id,
      "code" => "60100",
      "status" => "active",
      "target_type" => "PointAccount",
      "name" => "充值$100",
      "print_name" => "充值$100",
      "amount" => 10000
    })
    deposit_100 = Repo.insert!(changeset)

    changeset = Product.changeset(%Product{}, %{
      "account_id" => test_account1_id,
      "source_id" => deposit_100.id,
      "source_type" => "Depositable",
      "name_sync" => "sync_with_source",
      "maximum_public_order_quantity" => 9999,
      "source_quantity" => 1
    })
    product = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => test_account1_id,
      "product_id" => product.id,
      "status" => "active",
      "name" => "原价",
      "charge_amount_cents" => 10000,
      "charge_unit" => "EA",
      "order_unit" => "EA"
    })
    Repo.insert!(changeset)

    changeset = Product.changeset(product, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    Repo.insert!(%ProductCollectionMembership{
      account_id: test_account1_id,
      collection_id: deposit_pc.id,
      product_id: product.id
    })


    ########################
    # 李锦记熊猫蚝油
    ########################
    changeset = Stockable.changeset(%Stockable{}, %{
      "account_id" => account1_id,
      "code" => "100504",
      "status" => "active",
      "name" => "李锦记熊猫蚝油",
      "print_name" => "OYSTER FLAVOURED SAUCE",
      "unit_of_measure" => "瓶",
      "stackable" => false,
      "storage_type" => "room",
      "specification" => "每瓶510克。",
      "storage_description" => "常温保存，避免爆嗮。"
    })
    stockable_oyster_sauce = Repo.insert!(changeset)

    changeset = Stockable.changeset(stockable_oyster_sauce, %{
      "name" => "Oyster Flavoured Sauce",
      "specification" => "510g per bottle",
      "storage_description" => "Store in room temperature, avoid direct sun light."
    }, "en", account1.default_locale)
    Repo.update!(changeset)

    ########################
    # 老干妈豆豉辣椒油
    ########################
    changeset = Stockable.changeset(%Stockable{}, %{
      "account_id" => account1_id,
      "code" => "100502",
      "status" => "active",
      "name" => "老干妈豆豉辣椒油",
      "print_name" => "CHILI OIL BLACK BEAN",
      "unit_of_measure" => "瓶",
      "stackable" => false,
      "storage_type" => "room",
      "specification" => "每瓶280克。",
      "storage_description" => "常温保存，避免爆嗮，开启后冷藏。"
    })
    stockable_chili_oil = Repo.insert!(changeset)

    changeset = Stockable.changeset(stockable_chili_oil, %{
      "name" => "Chili Oil with Black Bean",
      "specification" => "280g per bottle",
      "storage_description" => "Store in room temperature, avoid direct sun light. After open keep refrigerated."
    }, "en", account1.default_locale)
    Repo.update!(changeset)

    ########################
    # 李锦记蒸鱼豉油
    ########################
    changeset = Stockable.changeset(%Stockable{}, %{
      "account_id" => account1_id,
      "code" => "100503",
      "status" => "active",
      "name" => "李锦记蒸鱼豉油",
      "print_name" => "SEASONED SOY SAUCE",
      "unit_of_measure" => "瓶",
      "stackable" => false,
      "storage_type" => "room",
      "specification" => "每瓶410毫升。",
      "storage_description" => "常温保存，避免爆嗮。"
    })
    stockable_seasoned_soy_sauce = Repo.insert!(changeset)

    changeset = Stockable.changeset(stockable_seasoned_soy_sauce, %{
      "name" => "Seasoned Soy Sauce",
      "specification" => "410ml per bottle",
      "storage_description" => "Store in room temperature, avoid direct sun light."
    }, "en", account1.default_locale)
    Repo.update!(changeset)

    ########################
    # 鱼
    ########################
    changeset = Stockable.changeset(%Stockable{}, %{
      "account_id" => account1_id,
      "code" => "100508",
      "status" => "active",
      "name" => "鱼",
      "print_name" => "FISH",
      "unit_of_measure" => "条",
      "stackable" => false,
      "storage_type" => "cool",
      "specification" => "每条约2磅",
      "storage_description" => "冷藏保存"
    })
    stockable_fish = Repo.insert!(changeset)

    changeset = Stockable.changeset(stockable_fish, %{
      "name" => "Fish",
      "specification" => "About 2lb per fish",
      "storage_description" => "Keep refrigerated"
    }, "en", account1.default_locale)
    Repo.update!(changeset)

    #######
    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "status" => "draft",
      "kind" => "with_variants",
      "name" => "调料"
    })
    product = Repo.insert!(changeset)

    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "kind" => "variant",
      "parent_id" => product.id,
      "source_id" => stockable_seasoned_soy_sauce.id,
      "source_type" => "Stockable",
      "name_sync" => "sync_with_source",
      "maximum_public_order_quantity" => 9999,
      "sort_index" => 9999,
      "source_quantity" => 1,
      "primary" => true
    })
    item_seasoned_soy_sauce = Repo.insert!(changeset)

    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "kind" => "variant",
      "parent_id" => product.id,
      "source_id" => stockable_oyster_sauce.id,
      "source_type" => "Stockable",
      "name_sync" => "sync_with_source",
      "maximum_public_order_quantity" => 9999,
      "sort_index" => 9999,
      "source_quantity" => 1
    })
    item_oyster_sauce = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_id" => item_seasoned_soy_sauce.id,
      "status" => "active",
      "name" => "Regular",
      "charge_amount_cents" => 599,
      "charge_unit" => "EA"
    })
    Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_id" => item_oyster_sauce.id,
      "status" => "active",
      "name" => "原价",
      "charge_amount_cents" => 1099,
      "charge_unit" => "EA"
    })
    Repo.insert!(changeset)

    changeset = Product.changeset(item_seasoned_soy_sauce, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    changeset = Product.changeset(item_oyster_sauce, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    changeset = Product.changeset(product, %{
      "status" => "active"
    })
    Repo.update!(changeset)
    ######

    ######
    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "status" => "draft",
      "source_id" => stockable_fish.id,
      "source_type" => "Stockable",
      "name_sync" => "sync_with_source",
      "maximum_public_order_quantity" => 9999,
      "sort_index" => 9999,
      "source_quantity" => 1,
    })
    product = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_id" => product.id,
      "status" => "active",
      "name" => "原价",
      "estimate_by_default" => true,
      "estimate_average_percentage" => 200,
      "estimate_maximum_percentage" => 250,
      "charge_amount_cents" => 1599,
      "charge_unit" => "磅",
      "order_unit" => "EA"
    })
    Repo.insert!(changeset)

    changeset = Product.changeset(product, %{
      "status" => "active"
    })
    Repo.update!(changeset)
    #####

    #######
    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "status" => "draft",
      "kind" => "combo",
      "maximum_public_order_quantity" => 9999,
      "name" => "调料套餐"
    })
    product = Repo.insert!(changeset)

    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "parent_id" => product.id,
      "source_id" => stockable_oyster_sauce.id,
      "source_type" => "Stockable",
      "status" => "active",
      "kind" => "item",
      "name_sync" => "sync_with_source",
      "sort_index" => 9999,
      "source_quantity" => 1
    })
    item_oyster_sauce = Repo.insert!(changeset)

    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "parent_id" => product.id,
      "source_id" => stockable_chili_oil.id,
      "source_type" => "Stockable",
      "status" => "active",
      "kind" => "item",
      "name_sync" => "sync_with_source",
      "sort_index" => 9999,
      "source_quantity" => 1
    })
    item_chili_oil = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_id" => product.id,
      "status" => "active",
      "name" => "原价",
      "charge_amount_cents" => 1100,
      "charge_unit" => "EA"
    })
    price = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_id" => item_oyster_sauce.id,
      "parent_id" => price.id,
      "name" => "原价",
      "charge_amount_cents" => 500
    })
    Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_id" => item_chili_oil.id,
      "parent_id" => price.id,
      "name" => "原价",
      "charge_amount_cents" => 600
    })
    Repo.insert!(changeset)

    changeset = Product.changeset(item_oyster_sauce, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    changeset = Product.changeset(item_chili_oil, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    changeset = Product.changeset(product, %{
      "status" => "active"
    })
    Repo.update!(changeset)
    ######

    # changeset = Unlockable.changeset(%Unlockable{}, %{
    #   "account_id" => account1_id,
    #   "code" => "HS001",
    #   "status" => "active",
    #   "name" => "New Associate Trainning",
    #   "print_name" => "NEW ASSOC TRAIN",
    #   "caption" => "Get it",
    #   "description" => "Now"
    # })
    # unlockable = Repo.insert!(changeset)

    # changeset = Product.changeset(%Product{}, %{
    #   "account_id" => account1_id,
    #   "source_id" => unlockable.id,
    #   "source_type" => "Unlockable",
    #   "status" => "draft",
    #   "name" => "Unlockable Product",
    #   "name_sync" => "sync_with_source",
    #   "primary" => true,
    #   "maximum_public_order_quantity" => 9999,
    #   "sort_index" => 9999,
    #   "source_quantity" => 1,
    #   "caption" => "Get it",
    #   "description" => "Now"
    # })
    # product = Repo.insert!(changeset)

    # changeset = Price.changeset(%Price{}, %{
    #   "account_id" => account1_id,
    #   "product_id" => product.id,
    #   "status" => "active",
    #   "name" => "原价",
    #   "charge_amount_cents" => 300,
    #   "charge_unit" => "EA"
    # })
    # Repo.insert!(changeset)

    # changeset = Product.changeset(product, %{
    #   "status" => "active"
    # })
    # Repo.update!(changeset)
  end
end