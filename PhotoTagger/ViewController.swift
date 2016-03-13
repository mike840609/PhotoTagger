/*
* Copyright (c) 2015 Razeware LLC
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*/

import UIKit
import Alamofire


class ViewController: UIViewController {
  
  // MARK: - IBOutlets
  @IBOutlet var takePictureButton: UIButton!
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var progressView: UIProgressView!
  @IBOutlet var activityIndicatorView: UIActivityIndicatorView!
  
  // MARK: - Properties
  private var tags: [String]?
  private var colors: [PhotoColor]?
  
  // MARK: - View Life Cycle
  override func viewDidLoad() {
    super.viewDidLoad()
    
    if !UIImagePickerController.isSourceTypeAvailable(.Camera) {
      takePictureButton.setTitle("Select Photo", forState: .Normal)
    }
  }
  
  override func viewDidDisappear(animated: Bool) {
    super.viewDidDisappear(animated)
    
    imageView.image = nil
  }
  
  // MARK: - Navigation
  override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
    
    if segue.identifier == "ShowResults" {
      guard let controller = segue.destinationViewController as? TagsColorsViewController else {
        fatalError("Storyboard mis-configuration. Controller is not of expected type TagsColorsViewController")
      }
      
      controller.tags = tags
      controller.colors = colors
    }
  }
  
  // MARK: - IBActions
  @IBAction func takePicture(sender: UIButton) {
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.allowsEditing = false
    
    if UIImagePickerController.isSourceTypeAvailable(.Camera) {
      picker.sourceType = UIImagePickerControllerSourceType.Camera
    } else {
      picker.sourceType = .PhotoLibrary
      picker.modalPresentationStyle = .FullScreen
    }
    
    presentViewController(picker, animated: true, completion: nil)
  }
}

// MARK: - UIImagePickerControllerDelegate
extension ViewController : UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  
  func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {
    guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
      print("Info did not have the required UIImage for the Original Image")
      dismissViewControllerAnimated(true, completion: nil)
      return
    }
    
    imageView.image = image
    
    // 1.Hide the upload button, and show the progress view and activity view.
    takePictureButton.hidden = true
    progressView.progress = 0.0
    progressView.hidden = false
    activityIndicatorView.startAnimating()
    
    uploadImage(
      image,
      // 2.While the file uploads, you call the progress handler with an updated percent. This changes the amount of progress bar showing.
      progress: {[unowned self] percent in self.progressView.setProgress(percent, animated: true)},completion: { [unowned self] tags,colors in
        // 3.The completion handler executes when the upload finishes. This sets the state on the controls back to their original state.
        self.takePictureButton.hidden = false
        self.progressView.hidden = true
        self.activityIndicatorView.stopAnimating()
        
        self.tags = tags
        self.colors = colors
        
        // 5.Finally the Storyboard advances to the results screen after a successful (or unsuccessful) upload. The user interface doesn’t change based on the error condition.
        self.performSegueWithIdentifier("ShowResults", sender: self)
        
        
      })
    
    
    
    dismissViewControllerAnimated(true, completion: nil)
  }
}


// Networking calls
extension ViewController {
  
  func uploadImage(image: UIImage, progress: (percent: Float) -> Void,
    completion: (tags: [String], colors: [PhotoColor]) -> Void) {
      
      // 如果不符合條件則列印字,符合條件繼續
      guard let imageData = UIImageJPEGRepresentation(image, 0.5) else {
        print("Could not get JPEG representation of UIImage")
        return
      }
      
      // Call Alamofire upload
      Alamofire.upload(ImaggaRouter.Content,
        multipartFormData: { multipartFormData in
          multipartFormData.appendBodyPart(data: imageData, name: "imagefile",
            fileName: "image.jpg", mimeType: "image/jpeg")
        },
        encodingCompletion: { encodingResult in
          
          switch encodingResult {
          case .Success(let upload, _, _):
            upload.progress { bytesWritten, totalBytesWritten, totalBytesExpectedToWrite in
              dispatch_async(dispatch_get_main_queue()) {
                let percent = (Float(totalBytesWritten) / Float(totalBytesExpectedToWrite))
                progress(percent: percent)
              }
            }
            upload.validate()
            upload.responseJSON { response in
              
              // 1.Check if the response was successful; if not, print the error and call the completion handler.
              guard response.result.isSuccess else {
                print("Error while uploading file: \(response.result.error)")
                completion(tags: [String](), colors: [PhotoColor]())
                return
              }
              // 2.Check each portion of the response, verifying the expected type is the actual type received. Retrieve the firstFileID from the response. If firstFileID cannot be resolved, print out an error message and call the completion handler.
              guard let responseJSON = response.result.value as? [String: AnyObject],
                uploadedFiles = responseJSON["uploaded"] as? [AnyObject],
                firstFile = uploadedFiles.first as? [String: AnyObject],
                firstFileID = firstFile["id"] as? String else {
                  print("Invalid information received from service")
                  completion(tags: [String](), colors: [PhotoColor]())
                  return
              }
              
              print("Content uploaded with ID: \(firstFileID)")
              
              // 3.Call the completion handler to update the UI. At this point, you don’t have any downloaded tags or colors, so simply call this with empty data.
              //completion(tags: [String](), colors: [PhotoColor]())
              
              self.downloadTags(firstFileID) { tags in
                self.downloadColors(firstFileID) { colors in
                  completion(tags: tags, colors: colors)
                }
              }
            }
            
          case .Failure(let encodingError):
            print(encodingError)
          }
          
      })
      
  }
  
  
  func downloadTags(contentID: String, completion: ([String]) -> Void) {
    
    Alamofire.request(
      .GET,
      "http://api.imagga.com/v1/tagging",
      parameters: ["content": contentID],
      headers: ["Authorization" : "Basic YWNjXzhlNDFhMTQzODRlYjM3YzplODE4YWU5NTFkYjAyNzdmZDNhYjZhMWU0OTcyNzdlOA=="]
      )
      .responseJSON { response in
        
        // 1.Check if the response was successful; if not, print the error and call the completion handler.
        guard response.result.isSuccess else {
          print("Error while fetching tags: \(response.result.error)")
          completion([String]())
          return
        }
        
        // 2.Check each portion of the response, verifying the expected type is the actual type received. Retrieve the tagsAndConfidences information from the response. If tagsAndConfidences cannot be resolved, print out an error message and call the completion handler.
        guard let responseJSON = response.result.value as? [String: AnyObject],
          results = responseJSON["results"] as? [AnyObject],
          firstResult = results.first,
          tagsAndConfidences = firstResult["tags"] as? [[String: AnyObject]] else {
            print("Invalid tag information received from the service")
            completion([String]())
            return
        }
        
        // 3.flatMap方法去處理每個在tagsAndConfidences字典中的值 並用？驗證是否可以轉換成一字串
        let tags = tagsAndConfidences.flatMap({ dict in
          return dict["tag"] as? String
        })
        
        // 4.Call the completion handler 回傳從server撈到的資料
        completion(tags)
    }
  }
  
  
  func downloadColors(contentID: String, completion: ([PhotoColor]) -> Void) {
    Alamofire.request(
      .GET,
      "http://api.imagga.com/v1/colors",
      parameters: ["content": contentID, "extract_object_colors": NSNumber(int: 0)],
      headers: ["Authorization" : "Basic YWNjXzhlNDFhMTQzODRlYjM3YzplODE4YWU5NTFkYjAyNzdmZDNhYjZhMWU0OTcyNzdlOA=="]
      )
      .responseJSON { response in
        
        guard response.result.isSuccess else {
          print("Error while fetching colors: \(response.result.error)")
          completion([PhotoColor]())
          return
        }
        
        
        guard let responseJSON = response.result.value as? [String: AnyObject],
          results = responseJSON["results"] as? [AnyObject],
          firstResult = results.first as? [String: AnyObject],
          info = firstResult["info"] as? [String: AnyObject],
          imageColors = info["image_colors"] as? [[String: AnyObject]] else {
            print("Invalid color information received from service")
            completion([PhotoColor]())
            return
        }
        
        // Using flatMap again, you iterate over the returned imageColors, transforming the data into PhotoColor objects which pairs colors in the RGB format with the color name as a string. Note the provided closure allows returning nil values since flatMap will simply ignore them.
        let photoColors = imageColors.flatMap({ (dict) -> PhotoColor? in
          guard let r = dict["r"] as? String,
            g = dict["g"] as? String,
            b = dict["b"] as? String,
            closestPaletteColor = dict["closest_palette_color"] as? String else {
              return nil
          }
          return PhotoColor(red: Int(r),
            green: Int(g),
            blue: Int(b),
            colorName: closestPaletteColor)
        })
        
        // 5.
        completion(photoColors)
    }
  }
  
  
  
  
}