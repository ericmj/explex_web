defmodule Hexpm.BillingTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.AuditLogs

  describe "create/2" do
    test "returns {:ok, whatever} when impl().create/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:ok, :whatever} end)

      assert Hexpm.Billing.create(%{},
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) ==
               {:ok, :whatever}
    end

    test "creates an Audit Log for billing.create when impl().create/1 succeeds" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:ok, %{}} end)

      user = insert(:user)

      Hexpm.Billing.create(%{},
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [audit_log] = AuditLogs.all_by(user)
    end

    test "returns {:error, reason} when impl().create/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:error, :reason} end)

      assert Hexpm.Billing.create(%{},
               audit: %{audit_data: {insert(:user), "Test User Agent"}, organization: nil}
             ) ==
               {:error, :reason}
    end

    test "does not create an Audit Log when impl().create/1 fails" do
      Mox.stub(Hexpm.Billing.Mock, :create, fn _params -> {:error, :reason} end)

      user = insert(:user)

      Hexpm.Billing.create(%{},
        audit: %{audit_data: {user, "Test User Agent"}, organization: nil}
      )

      assert [] = AuditLogs.all_by(user)
    end
  end
end
