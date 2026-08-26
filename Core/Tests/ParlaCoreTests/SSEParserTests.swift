import Testing
@testable import ParlaCore

private func run(_ lines: [String]) -> [SSEEvent] {
    var parser = SSEParser()
    return lines.flatMap { parser.consume(line: $0) }
}

@Test func extraeLosDeltasDeTexto() {
    let events = run([
        #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
        "",
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        "",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"eng"}}"#,
        "",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lish\":\"Hi\"}"}}"#,
        "",
        #"data: {"type":"message_stop"}"#,
        "",
    ])
    #expect(events == [.textDelta("{\"eng"), .textDelta("lish\":\"Hi\"}"), .done])
}

@Test func ignoraLosBloquesDePensamiento() {
    let events = run([
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#,
        "",
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"mmm"}}"#,
        "",
        #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
        "",
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"real"}}"#,
        "",
    ])
    #expect(events == [.textDelta("real")])
}

@Test func capturaElStopReason() {
    let events = run([
        #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":3}}"#,
        "",
    ])
    #expect(events == [.messageDelta(stopReason: "refusal")])
}

@Test func ignoraLineasDeEventoComentarioYVacias() {
    let events = run([
        "event: content_block_delta",
        ": ping",
        "",
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}}"#,
    ])
    #expect(events == [.textDelta("x")])
}

@Test func ignoraJSONCorrupto() {
    let events = run([#"data: {roto"#])
    #expect(events.isEmpty)
}
