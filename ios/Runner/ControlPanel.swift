import UIKit

protocol ControlPanelDelegate: AnyObject {
    func controlPanelDidTapStart(_ panel: ControlPanel)
    func controlPanelDidTapStop(_ panel: ControlPanel)
    func controlPanelDidTapRestart(_ panel: ControlPanel)
    func controlPanelDidTapPreview(_ panel: ControlPanel)
    func controlPanel(_ panel: ControlPanel, didRequestExportAs format: ExportFormat)
}

enum ExportFormat {
    case json
    case ply
    case zip  // ✅ Added ZIP export option
}

class ControlPanel: UIStackView {
    let statusLabel = UILabel()
    let actionButtons = UIStackView()
    
    let startButton = UIButton()
    let stopButton = UIButton()
    let restartButton = UIButton()
    let previewButton = UIButton()
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
        
        // Status Label
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.text = "Ready to scan"
        addArrangedSubview(statusLabel)
        statusLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        
        // Action Buttons
        actionButtons.axis = .horizontal
        actionButtons.spacing = 12
        actionButtons.distribution = .fillEqually
        addArrangedSubview(actionButtons)
        actionButtons.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        // Configure buttons
        configureButton(startButton, title: "Start", color: .systemGreen)
        configureButton(stopButton, title: "Stop", color: .systemRed)
        configureButton(restartButton, title: "Restart", color: .systemOrange)
        configureButton(previewButton, title: "Preview", color: .systemPurple)
        configureButton(exportButton, title: "Export", color: .systemBlue)
        
        // Initial state
        updateUIForScanningState(isScanning: false, hasMeshes: false)
    }
    
    private func configureButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.backgroundColor = color.withAlphaComponent(0.8)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        actionButtons.addArrangedSubview(button)
    }
    
    private func setupButtonActions() {
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)
        previewButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
    }
    
    @objc private func startTapped() { delegate?.controlPanelDidTapStart(self) }
    @objc private func stopTapped() { delegate?.controlPanelDidTapStop(self) }
    @objc private func restartTapped() { delegate?.controlPanelDidTapRestart(self) }
    @objc private func previewTapped() { delegate?.controlPanelDidTapPreview(self) }
    
    @objc private func exportTapped() {
        let alert = UIAlertController(title: "Export Options",
                                    message: "Choose export format",
                                    preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "JSON", style: .default) { _ in
            self.delegate?.controlPanel(self, didRequestExportAs: .json)
        })
        
        alert.addAction(UIAlertAction(title: "PLY", style: .default) { _ in
            self.delegate?.controlPanel(self, didRequestExportAs: .ply)
        })
        
        alert.addAction(UIAlertAction(title: "ZIP", style: .default) { _ in
            self.delegate?.controlPanel(self, didRequestExportAs: .zip)  // ✅ ZIP option
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let vc = parentViewController {
            alert.popoverPresentationController?.sourceView = exportButton
            alert.popoverPresentationController?.sourceRect = exportButton.bounds
            vc.present(alert, animated: true)
        }
    }
    
    func updateStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = text
        }
    }
    
    func updateUIForScanningState(isScanning: Bool, hasMeshes: Bool) {
        DispatchQueue.main.async {
            self.startButton.isHidden = isScanning || hasMeshes
            self.stopButton.isHidden = !isScanning
            self.restartButton.isHidden = !hasMeshes
            self.previewButton.isHidden = !hasMeshes
            self.exportButton.isHidden = !hasMeshes
        }
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
