import AWSLambdaRuntime

struct Input: Codable {
    enum Operation: String, Codable {
        case add
        case sub
        case mul
        case div
    }
    let a: Double
    let b: Double
    let op: Operation
}

struct Output: Codable {
    let result: Double
}


Lambda.run { (context, input: Input, callback: @escaping (Result<Output, Error>) -> Void) in
    let result: Double

    switch input.op {
    case .add:
        result = input.a + input.b
    case .sub:
        result = input.a - input.b
    case .mul:
        result = input.a * input.b
    case .div:
        result = input.a / input.b
    }
    
    callback(.success(Output(result: result)))
}
