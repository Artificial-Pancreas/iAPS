//
//  BasalStateView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import SwiftUI

public struct BasalStateSwiftUIView: UIViewRepresentable {

    var netBasalPercent: Double
    
    public init(netBasalPercent: Double) {
        self.netBasalPercent = netBasalPercent
    }
    
    public func makeUIView(context: UIViewRepresentableContext<BasalStateSwiftUIView>) -> BasalStateView {
        let view = BasalStateView()
        view.netBasalPercent = netBasalPercent
        return view
    }

    public func updateUIView(_ uiView: BasalStateView, context: UIViewRepresentableContext<BasalStateSwiftUIView>) {
        uiView.netBasalPercent = netBasalPercent
    }
}


public final class BasalStateView: UIView {
    
    var netBasalPercent: Double = 0 {
        didSet {
            animateToPath(drawPath())
        }
    }

    override public class var layerClass : AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        shapeLayer.lineWidth = 2
        updateTintColor()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        shapeLayer.lineWidth = 2
        updateTintColor()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        animateToPath(drawPath())
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        updateTintColor()
    }

    private func updateTintColor() {
        shapeLayer.fillColor = tintColor.withAlphaComponent(0.5).cgColor
        shapeLayer.strokeColor = tintColor.cgColor
    }

    private func drawPath() -> CGPath {
        let startX = bounds.minX
        let endX = bounds.maxX
        let midY = bounds.midY

        let path = UIBezierPath()
        path.move(to: CGPoint(x: startX, y: midY))

        let leftAnchor = startX + 1/6 * bounds.size.width
        let rightAnchor = startX + 5/6 * bounds.size.width

        let yAnchor = bounds.midY - CGFloat(netBasalPercent) * (bounds.size.height - shapeLayer.lineWidth) / 2

        path.addLine(to: CGPoint(x: leftAnchor, y: midY))
        path.addLine(to: CGPoint(x: leftAnchor, y: yAnchor))
        path.addLine(to: CGPoint(x: rightAnchor, y: yAnchor))
        path.addLine(to: CGPoint(x: rightAnchor, y: midY))
        path.addLine(to: CGPoint(x: endX, y: midY))

        return path.cgPath
    }

    private static let animationKey = "com.loudnate.Naterade.shapePathAnimation"

    private func animateToPath(_ path: CGPath) {
        // Do not animate first draw
        if shapeLayer.path != nil {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = shapeLayer.path ?? drawPath()
            animation.toValue = path
            animation.duration = 1
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            shapeLayer.add(animation, forKey: type(of: self).animationKey)
        }

        // Do not draw when size is zero
        if bounds != .zero {
            shapeLayer.path = path
        }
    }
}

struct BasalStateSwiftUIViewPreviewWrapper: View {
    @State private var percent: Double = 1
    
    var body: some View {
        VStack(spacing: 20) {
            BasalStateSwiftUIView(netBasalPercent: percent).frame(width: 100, height: 100, alignment: .center)
            Button(action: {
                self.percent = self.percent * -1
            }) {
                Text("Toggle sign")
            }
            Text("Percent = \(percent)")
        }
    }
}
struct BasalStateSwiftUIViewPreview: PreviewProvider {
    static var previews: some View {
        BasalStateSwiftUIViewPreviewWrapper()
    }
}
