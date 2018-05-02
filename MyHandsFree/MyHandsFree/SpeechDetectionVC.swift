//
//  SpeechDetectionVC.swift
//  MyHandsFree
//
//  Created by Tejas Chaphalkar on 4/30/18.
//  Copyright © 2018 Tejas Chaphalkar. All rights reserved.
//

import AVFoundation
import UIKit
import Speech

public enum CurrentAction: String {
    case text = "text"
    case music = "music"
    case unknown = "unknown"
    case photos = "photos"
    case call = "call"
}

class SpeechDetectionVC: UIViewController, SFSpeechRecognizerDelegate {
    
    @IBOutlet weak var microPhoneButton: UIButton!
    @IBOutlet weak var detectedTextLabel: UILabel!
    
    let synthesizer = AVSpeechSynthesizer()
    let audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    var bufferRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    var recognitionTask: SFSpeechRecognitionTask?
    var isRecording = false
    var enteringCellNumber = false
    var enteringTextNumber = false
    var cellNumber = "+1"
    var lastString: String = ""
    var currentAction = CurrentAction.unknown
    
    override func viewDidLoad() {
        super.viewDidLoad()
        requestSpeechAuthorization { [weak self] (authorized) in
            if authorized {
                self?.requestForMicroPhoneAccess(completion: { (authorized) in
                    if authorized {
                        let welcomeString = "Hello there! What would you like to do?"
                        let utterance = AVSpeechUtterance(string: welcomeString)
                        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                        self?.synthesizer.delegate = self
                        // TODO: add completion for requestSpeech
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self?.synthesizer.speak(utterance)
                        }
                    }
                })
            }
        }
    }
    
    //MARK: IBActions and Cancel
    func startListening() {
        bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        if isRecording == false {
            self.recordAndRecognizeSpeech()
            isRecording = true
        }
    }
    
    func cancelRecording() {
        audioEngine.stop()
        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)
        recognitionTask?.cancel()
    }
    
    func stopRecording() {
        if isRecording == true {
            bufferRequest?.endAudio()
            audioEngine.stop()
            let node = audioEngine.inputNode
            node.removeTap(onBus: 0)
            recognitionTask?.cancel()
            isRecording = false
        }
    }
    
    func recordAndRecognizeSpeech() {
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.bufferRequest?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.sendAlert(message: "There has been an audio engine error.")
            return print("SpeechDetectionVC: \(error)")
        }
        guard let myRecognizer = SFSpeechRecognizer() else {
            self.sendAlert(message: "Speech recognition is not supported for your current locale.")
            return
        }
        if !myRecognizer.isAvailable {
            self.sendAlert(message: "Speech recognition is not currently available. Check back at a later time.")
            // Recognizer is not available right now
            return
        }
        
        var alertTask: DispatchWorkItem? = nil
        if bufferRequest == nil {
            bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        }
        recognitionTask = speechRecognizer?.recognitionTask(with: bufferRequest!, resultHandler: { [weak self] result, error in
            if let result = result {
                print("SpeechDetectionVC: result: \(result.bestTranscription.formattedString) last string: \(self?.lastString)")
                if result.bestTranscription.formattedString == self?.lastString {
                    print("SpeechDetectionVC: return since last string and result is same")
                    return
                }
                alertTask?.cancel()
                if self?.enteringCellNumber == true {
                    let bestString = result.bestTranscription.formattedString
                    
                    let numbersRange = bestString.rangeOfCharacter(from: .decimalDigits)
                    if numbersRange == nil {
                        self?.performAction(for: bestString)
                    } else {
                        if let number = bestString.last {
                            let numberStr = String(describing: number)
                            self?.performAction(for: numberStr)
                        }
                    }
                    self?.lastString = ""
                } else {
                    alertTask = DispatchWorkItem { [weak self] in
                        self?.stopRecording()
                        self?.endOfSpeech(resultString: self?.lastString ?? "")
                    }
                    
                    // execute task in 3 seconds
                    if let dTask = alertTask {
                        let delay = DispatchTime.now() + .seconds(3)
                        DispatchQueue.main.asyncAfter(deadline: delay, execute: dTask)
                    }
                    
                    if result.isFinal {
                        self?.stopRecording()
                        self?.endOfSpeech(resultString: result.bestTranscription.formattedString)
                    }
                }
                self?.lastString = result.bestTranscription.formattedString
                self?.detectedTextLabel.text = self?.lastString
            } else if let error = error {
//                self?.sendAlert(message: "There has been a speech recognition error.")
                print("SpeechDetectionVC: \(error)")
            }
        })
    }
    
    func endOfSpeech(resultString: String) {
        print("SpeechDetectionVC: endOfSpeech \(resultString)")
        performAction(for: resultString)
        lastString = ""
        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)
    }
    
    //MARK - Check Authorization Status
    func requestForMicroPhoneAccess(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission({ [weak self] authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                case true:
                    completion(true)
                case false:
                    self?.microPhoneButton.setImage(UIImage(named: "microphone_denied"), for: .normal)
                    self?.detectedTextLabel.text = "Microphone not yet authorized"
                    completion(false)
                }
            }
        })
    }
    
    func requestSpeechAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self?.microPhoneButton.isEnabled = true
                    completion(true)
                case .denied, .restricted, .notDetermined:
                    self?.microPhoneButton.setImage(UIImage(named: "microphone_denied"), for: .normal)
                    self?.detectedTextLabel.text = "Speech recognition not yet authorized"
                    completion(false)
                }
            }
        }
    }
    
    func sendText(text: String) {
        let sms_: String = "sms:+1\(cellNumber)&body=\(text)"
        if let strURL: String = sms_.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL.init(string: strURL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    func makeCall(to number: String) {
        if let url = URL(string: "tel://\(number)") {
            UIApplication.shared.open(url) { (result) in
                if result {
                    // The URL was delivered successfully!
                }
            }
        }
    }
    
    func requestForText() {
        guard enteringCellNumber == true && cellNumber.count == 12 else {
            return
        }
        stopRecording()
        enteringCellNumber = false
//        startListening()
        
        switch currentAction {
        case .call:
            makeCall(to: cellNumber)
        case .text:
            let welcomeString = "Enter the text you want to send to \(cellNumber)"
            let utterance = AVSpeechUtterance(string: welcomeString)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
            
            enteringTextNumber = true
        default:
            break
        }
    }
    
    func performAction(for resultString: String) {
        print("SpeechDetectionVC: performAction resultString: \(resultString)")
        let actionString = resultString.lowercased()
        switch actionString {
        case CurrentAction.text.rawValue:
            currentAction = CurrentAction.text
            let welcomeString = "Say the number you want to text"
            let utterance = AVSpeechUtterance(string: welcomeString)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
            cellNumber = "+1"
            enteringCellNumber = true
        case CurrentAction.photos.rawValue:
            currentAction = CurrentAction.photos
            if let url = URL(string: "photos-redirect://") {
                UIApplication.shared.open(url) { (result) in
                    if result {
                        // The URL was delivered successfully!
                    }
                }
            }
        case CurrentAction.call.rawValue:
            currentAction = CurrentAction.call
            let welcomeString = "Say the number you want to text"
            let utterance = AVSpeechUtterance(string: welcomeString)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
            cellNumber = "+1"
            enteringCellNumber = true
        case "one", "1":
            if enteringCellNumber {
                cellNumber.append("1")
            }
        case "two", "2":
            if enteringCellNumber {
                cellNumber.append("2")
            }
        case "three", "3":
            if enteringCellNumber {
                cellNumber.append("3")
            }
        case "four", "4":
            if enteringCellNumber {
                cellNumber.append("4")
            }
        case "five", "5":
            if enteringCellNumber {
                cellNumber.append("5")
            }
        case "six", "6":
            if enteringCellNumber {
                cellNumber.append("6")
            }
        case "seven", "7":
            if enteringCellNumber {
                cellNumber.append("7")
            }
        case "eight", "8":
            if enteringCellNumber {
                cellNumber.append("8")
            }
        case "nine", "9":
            if enteringCellNumber {
                cellNumber.append("9")
            }
        case "zero", "0":
            if enteringCellNumber {
                cellNumber.append("0")
            }
        case "stop", "cancel":
            let welcomeString = "Cancelling your request"
            let utterance = AVSpeechUtterance(string: welcomeString)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
        default:
            if currentAction == .text && enteringTextNumber {
                sendText(text: resultString)
            }
        }
        
        requestForText()
    }
    
    //MARK: - Alert
    
    func sendAlert(message: String) {
        let alert = UIAlertController(title: "Speech Recognizer Error", message: message, preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func microPhoneTapped(_ sender: Any) {
        if isRecording == true {
            return
        }
        requestSpeechAuthorization { [weak self] (authorized) in
            if authorized {
                self?.requestForMicroPhoneAccess(completion: { (authorized) in
                    if authorized {
                        let welcomeString = "Hello there! What would you like to do?"
                        let utterance = AVSpeechUtterance(string: welcomeString)
                        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                        self?.synthesizer.delegate = self
                        // TODO: add completion for requestSpeech
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self?.synthesizer.speak(utterance)
                        }
                        
                        return
                    } else {
                       self?.showCustomAlertForPermissions()
                    }
                })
            } else {
                self?.showCustomAlertForPermissions()
            }
        }
    }
    
    func showCustomAlertForPermissions() {
        let message = "This app needs access to microphone and speech recognition."
        
        let alertView = UIAlertController(title: "", message: message, preferredStyle: .alert)
        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            
        })
        
        alertView.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let url = URL(string:UIApplicationOpenSettingsURLString) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        })
        
        self.present(alertView, animated: false, completion: nil)
    }
}

extension UIButton {
    func pulsate() {
        let pulse = CASpringAnimation(keyPath: "transform.scale")
        pulse.duration = 0.6
        pulse.fromValue = 0.95
        pulse.toValue = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = 2
        pulse.initialVelocity = 0.5
        pulse.damping = 1.0
        layer.add(pulse, forKey: "pulse")
    }
    
    func flash() {
        let flash = CABasicAnimation(keyPath: "opacity")
        flash.duration = 0.5
        flash.fromValue = 1
        flash.toValue = 0.5
        flash.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
        flash.autoreverses = true
        flash.repeatCount = .infinity
        layer.add(flash, forKey: nil)
    }
    
    func shake() {
        let shake = CABasicAnimation(keyPath: "position")
        shake.duration = 0.1
        shake.repeatCount = 2
        shake.autoreverses = true
        
        let fromPoint = CGPoint(x: center.x - 5, y: center.y)
        let fromValue = NSValue(cgPoint: fromPoint)
        
        let toPoint = CGPoint(x: center.x + 5, y: center.y)
        let toValue = NSValue(cgPoint: toPoint)
        
        shake.fromValue = fromValue
        shake.toValue = toValue
        
        layer.add(shake, forKey: "position")
    }
}

extension SpeechDetectionVC: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        microPhoneButton.flash()
        startListening()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        
    }
}
