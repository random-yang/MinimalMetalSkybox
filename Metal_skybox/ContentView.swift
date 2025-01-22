//
//  ContentView.swift
//  Metal_skybox
//
//  Created by randomyang on 2025/1/22.
//

import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)
        mtkView.depthStencilPixelFormat = .depth32Float
        
        // 添加平移手势识别器
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePan(_:)))
        mtkView.addGestureRecognizer(panGesture)
        
        context.coordinator.setupMetal(with: mtkView)
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) { }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalView
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var pipelineState: MTLRenderPipelineState!
        var depthStencilState: MTLDepthStencilState!
        var vertexBuffer: MTLBuffer!
        var cubeTexture: MTLTexture!
        
        // 矩阵
        var projectionMatrix = matrix_identity_float4x4
        var viewMatrix = matrix_identity_float4x4
        
        // 添加相机角度变量
        private var cameraYaw: Float = 0.0
        private var cameraPitch: Float = 0.0
        
        init(_ parent: MetalView) {
            self.parent = parent
            super.init()
        }
        
        func setupMetal(with view: MTKView) {
            guard let device = view.device else { fatalError("Metal not supported") }
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            setupResources()
            setupPipeline()
            setupMatrices(viewSize: view.bounds.size)
        }
        
        private func setupResources() {
            // 创建立方体顶点数据 (36 vertices)
            let cubeVertices: [SIMD3<Float>] = [
                // 前面
                [-50,  50,  50], [ 50,  50,  50], [-50, -50,  50],
                [ 50,  50,  50], [ 50, -50,  50], [-50, -50,  50],
                // 右面
                [ 50,  50,  50], [ 50,  50, -50], [ 50, -50,  50],
                [ 50,  50, -50], [ 50, -50, -50], [ 50, -50,  50],
                // 后面
                [ 50,  50, -50], [-50,  50, -50], [ 50, -50, -50],
                [-50,  50, -50], [-50, -50, -50], [ 50, -50, -50],
                // 左面
                [-50,  50, -50], [-50,  50,  50], [-50, -50, -50],
                [-50,  50,  50], [-50, -50,  50], [-50, -50, -50],
                // 顶面
                [-50,  50, -50], [ 50,  50, -50], [-50,  50,  50],
                [ 50,  50, -50], [ 50,  50,  50], [-50,  50,  50],
                // 底面
                [-50, -50,  50], [ 50, -50,  50], [-50, -50, -50],
                [ 50, -50,  50], [ 50, -50, -50], [-50, -50, -50]
            ]
            
            vertexBuffer = device.makeBuffer(
                bytes: cubeVertices,
                length: cubeVertices.count * MemoryLayout<SIMD3<Float>>.stride,
                options: .storageModeShared
            )
            
            // 加载立方体贴图
            let textureLoader = MTKTextureLoader(device: device)
            cubeTexture = try? textureLoader.newTexture(
                name: "Skybox",
                scaleFactor: 1.0,
                bundle: nil,
                options: [
                    .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                    .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
                    // .cubeLayout: MTKTextureLoader.CubeLayout.vertical
                ]
            )
        }
        
        private func setupPipeline() {
            guard let library = device.makeDefaultLibrary() else { fatalError("Metal library not found") }

            // 创建顶点描述符
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3 // 位置
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
            
            // 配置管线描述符
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexDescriptor = vertexDescriptor // 关键修复点
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "skyboxVertex")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "skyboxFragment")
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            
            // 深度模板状态
            let depthStencilDescriptor = MTLDepthStencilDescriptor()
            depthStencilDescriptor.depthCompareFunction = .lessEqual
            depthStencilDescriptor.isDepthWriteEnabled = false
            depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)
            
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                fatalError("Pipeline creation failed: \(error)")
            }
        }
        
        private func setupMatrices(viewSize: CGSize) {
            // 投影矩阵
            let aspect = Float(viewSize.width / viewSize.height)
            projectionMatrix = matrix_perspective_right_hand(
                fovyRadians: radians(fromDegrees: 120),
                aspectRatio: aspect,
                nearZ: 0.1,
                farZ: 100
            )
            
            // 初始化视图矩阵
            updateViewMatrix()
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            
            // 转换平移距离为角度变化（调整灵敏度）
            let sensitivity: Float = 0.005
            cameraYaw -= Float(translation.x) * sensitivity
            cameraPitch += Float(translation.y) * sensitivity
            
            // 限制俯仰角度范围
            cameraPitch = max(-.pi/2 + 0.1, min(cameraPitch, .pi/2 - 0.1))
            
            // 重置手势位置
            gesture.setTranslation(.zero, in: gesture.view)
            
            // 更新相机矩阵
            updateViewMatrix()
        }
        
        private func updateViewMatrix() {
            // 计算相机方向向量
            let cosP = cos(cameraPitch)
            let sinP = sin(cameraPitch)
            let cosY = cos(cameraYaw)
            let sinY = sin(cameraYaw)
            
            let forwardVector = SIMD3<Float>(
                cosP * sinY,
                -sinP,
                cosP * cosY
            )
            
            let cameraPosition = SIMD3<Float>(0, 0, 0)
            viewMatrix = matrix_look_at_right_hand(
                eye: cameraPosition,
                target: cameraPosition + forwardVector,
                up: SIMD3<Float>(0, 1, 0)
            )
            viewMatrix.columns.3 = [0, 0, 0, 1] // 移除平移分量
        }
        
        // MARK: - MTKViewDelegate
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            setupMatrices(viewSize: size)
        }
        
        func draw(in view: MTKView) {
            guard let device = view.device,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable else { return }
            
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            
            encoder.setRenderPipelineState(pipelineState)
            encoder.setDepthStencilState(depthStencilState)
            
            // 绑定顶点缓冲
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            
            // 传递矩阵
            var viewProjectionMatrix = projectionMatrix * viewMatrix
            encoder.setVertexBytes(
                &viewProjectionMatrix,
                length: MemoryLayout<matrix_float4x4>.stride,
                index: 1
            )
            
            // 绑定纹理
            encoder.setFragmentTexture(cubeTexture, index: 0)
            
            // 绘制调用
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 36
            )
            
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        // 辅助函数
        private func radians(fromDegrees degrees: Float) -> Float {
            return degrees * .pi / 180
        }
        
        private func matrix_perspective_right_hand(fovyRadians: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
            let ys = 1 / tanf(fovyRadians * 0.5)
            let xs = ys / aspectRatio
            let zs = farZ / (nearZ - farZ)
            return matrix_float4x4(columns: (
                SIMD4(xs,  0, 0,   0),
                SIMD4( 0, ys, 0,   0),
                SIMD4( 0,  0, zs, -1),
                SIMD4( 0,  0, zs * nearZ, 0)
            ))
        }
        
        private func matrix_look_at_right_hand(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
            let z = normalize(eye - target)
            let x = normalize(cross(up, z))
            let y = cross(z, x)
            return matrix_float4x4(columns: (
                SIMD4(x.x, y.x, z.x, 0),
                SIMD4(x.y, y.y, z.y, 0),
                SIMD4(x.z, y.z, z.z, 0),
                SIMD4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
            ))
        }
    }
}

#Preview {
    MetalView()
}
