module TestJoin
    using Base.Test
    using DataFrames
    using DataArrays

    name = DataFrame(ID = [1, 2, 3], Name = ["John Doe", "Jane Doe", "Joe Blogs"])
    job = DataFrame(ID = [1, 2, 4], Job = ["Lawyer", "Doctor", "Farmer"])

    # Join on symbols or vectors of symbols
    join(name, job, on = :ID)
    join(name, job, on = [:ID])

    # Soon we won't allow natural joins
    #@test_throws join(name, job)

    # Test output of various join types
    outer = DataFrame(ID = [1, 2, 3, 4],
                      Name = @data(["John Doe", "Jane Doe", "Joe Blogs", NA]),
                      Job = @data(["Lawyer", "Doctor", NA, "Farmer"]))

    # (Tests use current column ordering but don't promote it)
    right = outer[!isna(outer[:Job]), [:Name, :ID, :Job]]
    left = outer[!isna(outer[:Name]), :]
    inner = left[!isna(left[:Job]), :]
    semi = inner[:, [:ID, :Name]]
    anti = left[isna(left[:Job]), [:ID, :Name]]
    
    @test isequal(join(name, job, on = :ID), inner)
    @test isequal(join(name, job, on = :ID, kind = :inner), inner)
    @test isequal(join(name, job, on = :ID, kind = :outer), outer)
    @test isequal(join(name, job, on = :ID, kind = :left), left)
    @test isequal(join(name, job, on = :ID, kind = :right), right)
    @test isequal(join(name, job, on = :ID, kind = :semi), semi)
    @test isequal(join(name, job, on = :ID, kind = :anti), anti)

    # Join on multiple keys
    df1 = DataFrame(A = 1, B = 2, C = 3)
    df2 = DataFrame(A = 1, B = 2, D = 4)

    join(df1, df2, on = [:A, :B])

    # Test output of cross joins
    df1 = DataFrame(A = 1:2, B = 'a':'b')
    df2 = DataFrame(A = 1:3, C = 3:5)

    cross = DataFrame(A = [1, 1, 1, 2, 2, 2],
                      B = ['a', 'a', 'a', 'b', 'b', 'b'],
                      C = [3, 4, 5, 3, 4, 5])

    @test join(df1, df2[[:C]], kind = :cross) == cross

    # Cross joins handle naming collisions
    @test size(join(df1, df1, kind = :cross)) == (4, 4)

    # Cross joins don't take keys
    @test_throws join(df1, df2, on = :A, kind = :cross)
end
