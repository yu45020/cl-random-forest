;; set dynamic-space-size >= 2500

(in-package :cl-random-forest)

;;; Load Dataset ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; MNIST data
;; https://www.csie.ntu.edu.tw/~cjlin/libsvmtools/datasets/multiclass.html#mnist

(defparameter mnist-dim 784)
(defparameter mnist-n-class 10)

(let ((mnist-train (clol.utils:read-data "/home/wiz/tmp/mnist.scale" mnist-dim :multiclass-p t))
      (mnist-test (clol.utils:read-data "/home/wiz/tmp/mnist.scale.t" mnist-dim :multiclass-p t)))

  ;; Add 1 to labels in order to form class-labels beginning from 0
  (dolist (datum mnist-train) (incf (car datum)))
  (dolist (datum mnist-test)  (incf (car datum)))

  (multiple-value-bind (datamat target)
      (clol-dataset->datamatrix/target mnist-train)
    (defparameter mnist-datamatrix datamat)
    (defparameter mnist-target target))
  
  (multiple-value-bind (datamat target)
      (clol-dataset->datamatrix/target mnist-test)
    (defparameter mnist-datamatrix-test datamat)
    (defparameter mnist-target-test target)))

;;; Make Random Forest ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Enable/Disable parallelizaion
(setf lparallel:*kernel* (lparallel:make-kernel 4))
(setf lparallel:*kernel* nil)

;; 6.079 seconds (1 core), 2.116 seconds (4 core)
(defparameter mnist-forest
  (make-forest mnist-n-class mnist-datamatrix mnist-target
               :n-tree 500 :bagging-ratio 0.1 :max-depth 10 :n-trial 10 :min-region-samples 5))

;; 4.786 seconds, Accuracy: 93.38%
(test-forest mnist-forest mnist-datamatrix-test mnist-target-test)

;; 42.717 seconds (1 core), 13.24 seconds (4 core)
(defparameter mnist-forest-tall
  (make-forest mnist-n-class mnist-datamatrix mnist-target
               :n-tree 100 :bagging-ratio 1.0 :max-depth 15 :n-trial 28 :min-region-samples 5))

;; 2.023 seconds, Accuracy: 96.62%
(test-forest mnist-forest-tall mnist-datamatrix-test mnist-target-test)

;;; Global Refinement of Random Forest ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Generate sparse data from Random Forest

;; 6.255 seconds (1 core), 1.809 seconds (4 core)
(defparameter mnist-refine-dataset
  (make-refine-dataset mnist-forest mnist-datamatrix))

;; 0.995 seconds (1 core), 0.322 seconds (4 core)
(defparameter mnist-refine-test
  (make-refine-dataset mnist-forest mnist-datamatrix-test))

(defparameter mnist-refine-learner (make-refine-learner mnist-forest))

;; 4.347 seconds (1 core), 2.281 seconds (4 core), Accuracy: 98.259%
(train-refine-learner-process mnist-refine-learner mnist-refine-dataset mnist-target
                              mnist-refine-test mnist-target-test)

(test-refine-learner mnist-refine-learner mnist-refine-test mnist-target-test)

;; 5.859 seconds (1 core), 4.090 seconds (4 core), Accuracy: 98.29%
(loop repeat 5 do
  (train-refine-learner mnist-refine-learner mnist-refine-dataset mnist-target)
  (test-refine-learner mnist-refine-learner mnist-refine-test mnist-target-test))

;; Make a prediction
(predict-refine-learner mnist-forest mnist-refine-learner mnist-datamatrix-test 0)

;;; Global Prunning of Random Forest ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(length (collect-leaf-parent mnist-forest)) ; => 98008
(pruning! mnist-forest mnist-refine-learner 0.1) ; 0.328 seconds
(length (collect-leaf-parent mnist-forest)) ; => 93228

;; Re-learning refine learner
(defparameter mnist-refine-dataset (make-refine-dataset mnist-forest mnist-datamatrix))
(defparameter mnist-refine-test (make-refine-dataset mnist-forest mnist-datamatrix-test))
(defparameter mnist-refine-learner (make-refine-learner mnist-forest))
(time
 (loop repeat 10 do
   (train-refine-learner mnist-refine-learner mnist-refine-dataset mnist-target)
   (test-refine-learner mnist-refine-learner mnist-refine-test mnist-target-test)))

;; Accuracy: Accuracy: 98.27%

(loop repeat 10 do
  (sb-ext:gc :full t)
  (room)
  (format t "~%Making mnist-refine-dataset~%")
  (defparameter mnist-refine-dataset (make-refine-dataset mnist-forest mnist-datamatrix))
  (format t "Making mnist-refine-test~%")
  (defparameter mnist-refine-test (make-refine-dataset mnist-forest mnist-datamatrix-test))
  (format t "Re-learning~%")
  (defparameter mnist-refine-learner (make-refine-learner mnist-forest))
  (train-refine-learner-process mnist-refine-learner mnist-refine-dataset mnist-target
                                mnist-refine-test mnist-target-test)
  (test-refine-learner mnist-refine-learner mnist-refine-test mnist-target-test)
  (format t "Pruning. leaf-size: ~A" (length (collect-leaf-parent mnist-forest)))
  (pruning! mnist-forest mnist-refine-learner 0.5)
  (format t " -> ~A ~%" (length (collect-leaf-parent mnist-forest))))

;;; n-fold cross-validation

(defparameter n-fold 5)

(cross-validation-forest-with-refine-learner
 n-fold mnist-n-class mnist-datamatrix mnist-target
 :n-tree 100 :bagging-ratio 0.1 :max-depth 10 :n-trial 28 :gamma 10d0 :min-region-samples 5)