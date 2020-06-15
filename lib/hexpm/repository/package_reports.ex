defmodule Hexpm.Repository.PackageReports do
    use Hexpm.Context

    def add(params) do
        Repo.insert(
            PackageReport.build(
                params["releases"],
                params["user"],
                params["package"],
                params
            )
        )
    end
    
    def search(count, page, search) do
        PackageReport.all(count, page, search)
        |> Repo.all()
    end

    def count() do
        PackageReport.count()
        |> Repo.one()
    end

    def get(id) do
        PackageReport.get(id)
        |> Repo.one()
    end
end