defmodule BlueJet.Repo.Migrations.CreateDataImport do
  use Ecto.Migration

  def change do
    create table(:data_imports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :file_id, references(:files, type: :binary_id, on_delete: :nilify_all)

      add :status, :string
      add :data_url, :text
      add :data_type, :string

      add :data_count, :integer
      add :time_spent_seconds, :integer

      timestamps()
    end

    create index(:data_imports, [:account_id, :status])
  end
end