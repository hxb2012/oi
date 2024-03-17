const answer = @import("answer");

export fn main() c_int {
    answer.main() catch {
        return 1;
    };

    return 0;
}
