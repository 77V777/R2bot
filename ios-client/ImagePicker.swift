import Foundation
import SwiftUI
import UIKit

// Wrapper for UIImagePickerController to use camera and return JPEG Data
struct ImagePicker: UIViewControllerRepresentable {
    enum PickerError: Error {
        case cameraUnavailable
        case cancelled
        case unknown
    }

    var sourceType: UIImagePickerController.SourceType = .camera
    var completion: (Result<Data, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(.failure(PickerError.cancelled))
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true, completion: nil)
            guard let image = info[.originalImage] as? UIImage else {
                parent.completion(.failure(PickerError.unknown))
                return
            }
            // Convert to JPEG data
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                parent.completion(.failure(PickerError.unknown))
                return
            }
            parent.completion(.success(data))
        }
    }
}
