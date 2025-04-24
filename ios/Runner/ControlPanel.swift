import UIKit

protocol ControlPanelDelegate: AnyObject {
    func controlPanel(_ panel: ControlPanel, didTapButton button: UIButton)
    func controlPanel(_ panel: ControlPanel, didRequestExportAs format: ExportFormat)
}

enum ExportFormat {
    case json
    case ply
}

class ControlPanel: UIStackView {
    let statusLabel = UILabel()
    let actionButtons = UIStackView()
    
    let stopButton = UIButton()
    let restartButton = UIButton()
    let previewButton = UIButton()
    let saveButton = UIButton()
    let exportButton = UIButton()
    
    weak var delegate: ControlPanelDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupButtonActions()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupButtonActions()
    }
    
    private func setupUI() {
        axis = .vertical
        spacing = 12
        distribution = .fill
        
        // Configure status label
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.text = "Preparing scan..."
        addArrangedSubview(statusLabel)
        statusLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        // Configure action buttons
        actionButtons.axis = .horizontal
        actionButtons.spacing = 12
        actionButtons.distribution = .fillEqually
        addArrangedSubview(actionButtons)
        actionButtons.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        
        // Configure buttons
        stopButton.setTitle("Stop", for: .normal)
        stopButton.backgroundColor = .systemRed.withAlphaComponent(0.8)
        
        restartButton.setTitle("Restart", for: .normal)
        restartButton.backgroundColor = .systemOrange.withAlphaComponent(0.8)
        
        previewButton.setTitle("Preview", for: .normal)
        previewButton.backgroundColor = .systemPurple.withAlphaComponent(0.8)
        
        saveButton.setTitle("Save", for: .normal)
        saveButton.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        
        exportButton.setTitle("Export", for: .normal)
        exportButton.backgroundColor = .systemGreen.withAlphaComponent(0.8)
        
        // Add buttons
        [stopButton, restartButton, previewButton, saveButton, exportButton].forEach {
            configureButton($0)
            actionButtons.addArrangedSubview($0)
            $0.isHidden = true
        }
        
        stopButton.isHidden = false
    }
    
    private func configureButton(_ button: UIButton) {
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
    }
    
    private func setupButtonActions() {
        stopButton.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        restartButton.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        previewButton.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportButtonTapped(_:)), for: .touchUpInside)
    }
    
    @objc private func buttonTapped(_ sender: UIButton) {
        delegate?.controlPanel(self, didTapButton: sender)
    }
    
    @objc private func exportButtonTapped(_ sender: UIButton) {
        let alert = UIAlertController(title: "Export Options", message: "Choose export format", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "JSON", style: .default, handler: { _ in
            self.delegate?.controlPanel(self, didRequestExportAs: .json)
        }))
        
        alert.addAction(UIAlertAction(title: "PLY", style: .default, handler: { _ in
            self.delegate?.controlPanel(self, didRequestExportAs: .ply)
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let vc = self.parentViewController {
            alert.popoverPresentationController?.sourceView = sender
            alert.popoverPresentationController?.sourceRect = sender.bounds
            vc.present(alert, animated: true)
        }
    }
    
    func updateStatus(_ text: String) {
        statusLabel.text = text
    }
    
    func updateUIForScanningState(isScanning: Bool, hasMeshes: Bool) {
        stopButton.isHidden = !isScanning
        restartButton.isHidden = isScanning
        previewButton.isHidden = isScanning || !hasMeshes
        saveButton.isHidden = isScanning
        exportButton.isHidden = isScanning || !hasMeshes
    }
}

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while parentResponder != nil {
            parentResponder = parentResponder?.next
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}
