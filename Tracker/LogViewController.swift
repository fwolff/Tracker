//
//  LogViewController.swift
//  Tracker
//
//  Created by Franck Wolff on 10/28/16.
//  Copyright © 2016 4riders. All rights reserved.
//

import UIKit

class LogViewController: UIViewController {

    @IBOutlet weak var textView: UITextView!
    
    @IBAction func back(_ sender: UIButton) {
        dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        var fileUrl = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        fileUrl.appendPathComponent("application.log")
        
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            textView.text = try! String(contentsOfFile: fileUrl.path)
        }
    }
}
