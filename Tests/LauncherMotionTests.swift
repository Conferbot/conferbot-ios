import XCTest
@testable import Conferbot

final class LauncherMotionTests: XCTestCase {

    func testPacesIdleMomentsLikeTheWeb() {
        XCTAssertEqual(LauncherMotion.nextIdleDelay("subtle", played: 0), LauncherMotion.firstIdleMs)
        XCTAssertEqual(LauncherMotion.nextIdleDelay("subtle", played: 1), 30000)
        XCTAssertNil(LauncherMotion.nextIdleDelay("subtle", played: 4))
        XCTAssertEqual(LauncherMotion.nextIdleDelay("lively", played: 3, random: { 0.5 }), 24000)
        XCTAssertNil(LauncherMotion.nextIdleDelay("lively", played: 10))
        XCTAssertNil(LauncherMotion.nextIdleDelay("off", played: 0))
    }

    func testSolvesCssCubicBezier() {
        XCTAssertEqual(LauncherMotion.cubicBezier([0.42, 0, 0.58, 1], 0.5), 0.5, accuracy: 1e-3)
        XCTAssertEqual(LauncherMotion.cubicBezier([0, 0, 1, 1], 0.3), 0.3, accuracy: 1e-3)
        XCTAssertGreaterThan(LauncherMotion.cubicBezier([0.2, 1.4, 0.4, 1], 0.5), 1)
    }

    func testRipplesTwoRingsThenStops() {
        XCTAssertNil(LauncherMotion.rippleRing(2.0, ring: 0))
        let a = LauncherMotion.rippleRing(3.4, ring: 0)
        XCTAssertNotNil(a)
        XCTAssertGreaterThan(a!.scale, 1)
        XCTAssertLessThan(a!.opacity, 0.45)
        XCTAssertNil(LauncherMotion.rippleRing(2.7, ring: 1))
        XCTAssertNil(LauncherMotion.rippleRing(2.5 + 1.8 * 3 + 0.1, ring: 0))
    }

    func testRestsAfterTheMoment() {
        XCTAssertTrue(LauncherMotion.iconFrame(LauncherIcons.byId("WidgetBubbleIcon40")!, state: "idle", t: 9).allSatisfy { $0 == nil })
    }

    /// The same frames as the RN SDK's evaluator, which is checked against Chrome's own animation of the web icons.
    func testMatchesTheVerifiedEvaluator() throws {
        let cases = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(Self.golden.utf8)) as? [[String: Any]])
        for c in cases {
            let id = c["id"] as! String
            let frame = LauncherMotion.iconFrame(LauncherIcons.byId(id)!, state: c["st"] as! String, t: (c["t"] as! NSNumber).doubleValue)
            let ops = c["ops"] as! [Any]
            XCTAssertEqual(frame.count, ops.count, id)
            for (i, w) in ops.enumerated() {
                guard let want = w as? [String: Any] else { XCTAssertNil(frame[i], "(id) op (i)"); continue }
                let got = try XCTUnwrap(frame[i], "(id) op (i)")
                let m = (want["m"] as! [NSNumber]).map { $0.doubleValue }
                for k in 0..<6 { XCTAssertEqual(got.m[k], m[k], accuracy: 1e-3, "(id) op (i) m[(k)]") }
                let layers = want["layers"] as! [[NSNumber]]
                XCTAssertEqual(got.layers.count, layers.count, "(id) op (i) layers")
                for (k, l) in layers.enumerated() where k < got.layers.count {
                    XCTAssertEqual(got.layers[k].g, l[0].intValue)
                    XCTAssertEqual(got.layers[k].o, l[1].doubleValue, accuracy: 1e-3)
                }
            }
        }
    }

    static let golden = #"""
[{"id":"WidgetBubbleIcon40","st":"msg","t":0.2,"ops":[{"m":[1.06623,-0.1719,0.1719,1.06623,-3.07244,1.1852],"layers":[]},{"m":[1.06623,-0.1719,0.1719,1.06623,-3.07244,1.1852],"layers":[]},{"m":[1.06623,-0.1719,0.1719,1.06623,-3.07244,1.1852],"layers":[]},{"m":[1.06623,-0.1719,0.1719,1.06623,-3.07244,1.1852],"layers":[]}]},{"id":"WidgetBubbleIcon27","st":"idle","t":0.5,"ops":[{"m":[0.69463,-0.71952,0.71952,0.69463,-10.04448,8.97101],"layers":[]},{"m":[0.98481,-0.17361,0.17361,0.98481,-3.50664,2.30983],"layers":[]},{"m":[0.98481,-0.17361,0.17361,0.98481,-3.50664,2.30983],"layers":[]},{"m":[0.98481,-0.17361,0.17361,0.98481,-3.50664,2.30983],"layers":[]},{"m":[0.98481,-0.17361,0.17361,0.98481,-3.50664,2.30983],"layers":[]},{"m":[0.98481,-0.17361,0.17361,0.98481,-3.50664,2.30983],"layers":[]},{"m":[1,0,0,1,0,0],"layers":[[2,1]]},{"m":[1,0,0,1,0,0],"layers":[[2,1]]}]},{"id":"WidgetBubbleIcon53","st":"msg","t":0.7,"ops":[null,{"m":[0.65076,0.50871,-0.80375,1.02818,27.10125,-23.41303],"layers":[[1,0.03687]]},{"m":[0.788,0.616,-0.616,0.788,22.48783,-20.90568],"layers":[[1,0.03687]]},{"m":[0.788,0.616,-0.616,0.788,22.48783,-20.90568],"layers":[[1,0.03687]]},{"m":[0.788,0.616,-0.616,0.788,22.48783,-20.90568],"layers":[[1,0.03687]]},{"m":[0.788,0.616,-0.616,0.788,22.48783,-20.90568],"layers":[[1,0.03687]]},{"m":[0.788,0.616,-0.616,0.788,22.48783,-20.90568],"layers":[[1,0.03687]]},{"m":[0.788,0.616,-0.616,0.788,22.48783,-20.90568],"layers":[[1,0.03687]]}]},{"id":"WidgetBubbleIcon54","st":"idle","t":0.3,"ops":[null,{"m":[1.03747,0.07255,-0.07255,1.03747,1.40733,-1.01169],"layers":[]},{"m":[1.03747,0.07255,-0.07255,1.03747,1.40733,-1.01169],"layers":[]},{"m":[1.03747,0.07255,-0.07255,1.03747,1.40733,-1.01169],"layers":[]},{"m":[1,0,0,1,0,0],"layers":[[3,1]]},{"m":[1,0,0,1,0,0],"layers":[[4,1]]},{"m":[1,0,0,1,0,0],"layers":[[5,1]]},{"m":[1,0,0,1,0,0],"layers":[[6,0.99163]]},{"m":[1,0,0,1,0,0],"layers":[[7,1]]},{"m":[1,0,0,1,0,0],"layers":[[8,1]]}]},{"id":"WidgetBubbleIcon51","st":"msg","t":0.3,"ops":[null,{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[[2,0]]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[[3,1]]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[[3,1]]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[]},{"m":[1.01347,0,0,1.01347,-0.13473,-0.54791],"layers":[]},{"m":[1,0,0,1,0,0],"layers":[[5,0]]},{"m":[1,0,0,1,0,0],"layers":[[5,0]]}]},{"id":"WidgetBubbleIcon41","st":"idle","t":0.9,"ops":[null,null,null,null,{"m":[1,0,0,1,0,-0.64589],"layers":[]},{"m":[1,0,0,1,0,0],"layers":[]},{"m":[1,0,0,1,0,0],"layers":[]}]}]
"""#
}
