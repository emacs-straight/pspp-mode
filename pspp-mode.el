;;; pspp-mode.el --- Major mode for editing PSPP files  -*- lexical-binding: t; -*-

;; Copyright (C) 2005,2018,2020 Free Software Foundation, Inc.
;; Author: Scott Andrew Borton <scott@pp.htv.fi>
;; Maintainer: John Darrington <john@darrington.wattle.id.au>
;; Created: 05 March 2005
;; Version: 1.1
;; Keywords: PSPP major-mode
;; This file is not part of GNU Emacs.

;;; Commentary:
;; Based on the example wpdl-mode.el by Scott Borton

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Code:

(defvar pspp-mode-map
  (let ((map (make-keymap)))
    (define-key map "\C-j" 'newline-and-indent)
    map)
  "Keymap for PSPP major mode")


;;;###autoload
(add-to-list 'auto-mode-alist '("\\.sps\\'" . pspp-mode))


(defun pspp-data-block-p ()
  "Returns t if current line is inside a data block."
  (save-excursion
    (let ((pspp-end-of-block-found nil)
          (pspp-start-of-block-found nil))
      (beginning-of-line)
      (while (not (or
                   (or (bobp) pspp-end-of-block-found)
                   pspp-start-of-block-found))
        (setq pspp-end-of-block-found
              (looking-at "^[ \t]*\\(END\\|end\\)[\t ]+\\(DATA\\|data\\)\."))
        (setq pspp-start-of-block-found
              (looking-at "^[ \t]*\\(BEGIN\\|begin\\)[\t ]+\\(DATA\\|data\\)"))
        (forward-line -1))

      (and pspp-start-of-block-found (not pspp-end-of-block-found)))))


(defconst pspp-indent-width             ;FIXME: Should be a defcustom.
  2
  "Size of indent.")


(defun pspp--updown-list (l)
  "Takes a list of strings and returns that list with all elements upcased
and downcased"
  (append (mapcar #'upcase l) (mapcar #'downcase l)))


(defconst pspp-indenters
  (concat "^[\t ]*"
          (regexp-opt (pspp--updown-list '("DO"
                                     "BEGIN"
                                     "LOOP"
                                     "INPUT"))
                      t)
          "[\t ]+")
  "Constructs which cause indentation.")


(defconst pspp-unindenters
  (concat "^[\t ]*\\(END\\|end\\)[\t ]+"
          (regexp-opt (pspp--updown-list '("IF"
                                     "DATA"
                                     "LOOP"
                                     "REPEAT"
                                     "INPUT"))
                      t)
          "[\t ]*")
  ;; Note that "END CASE" and "END FILE" do not unindent.
  "Constructs which cause end of indentation.")


(defun pspp-indent-line ()
  "Indent current line as PSPP code."
  (beginning-of-line)
  (let (;; (verbatim nil)
        (the-indent 0)    ; Default indent to column 0
        (case-fold-search t))
    (if (bobp)
        (setq the-indent 0))  ; First line is always non-indented
    (let ((within-command nil) (blank-line t))
      ;; If the most recent non blank line ended with a `.' then
      ;; we're at the start of a new command.
      (save-excursion
        (while (and blank-line (not (bobp)))
          (forward-line -1)

          (if (and (not (pspp-data-block-p)) (not (looking-at "^[ \t]*$")))
              (progn
                (setq blank-line nil)

                (if (not (looking-at ".*\\.[ \t]*$"))
                    (setq within-command t))))))
      ;; If we're not at the start of a new command, then add an indent.
      (if within-command
          (setq the-indent (+ 1 the-indent))))
    ;; Set the indentation according to the DO - END blocks
    (save-excursion
      (beginning-of-line)
      (while (not (bobp))
        (beginning-of-line)
        (if (not (pspp-comment-p))
            (cond ((save-excursion
                     (forward-line -1)
                     (looking-at pspp-indenters))
                   (setq the-indent (+ the-indent 1)))

                  ((looking-at pspp-unindenters)
                   (setq the-indent (- the-indent 1)))))
        (forward-line -1)))

    (save-excursion
      (beginning-of-line)
      (if (looking-at "^[\t ]*ELSE")
          (setq the-indent (- the-indent 1))))

    ;; Stuff in the data-blocks should be untouched
    (if (not (pspp-data-block-p)) (indent-line-to (* pspp-indent-width the-indent)))))


(defun pspp-comment-start-line-p ()
  "Return t if the current line is the first line of a comment, nil otherwise"
  (beginning-of-line)
  (or (looking-at "^\\*")
      (looking-at "^[\t ]*comment[\t ]")
      (looking-at "^[\t ]*COMMENT[\t ]")))


(defun pspp-comment-end-line-p ()
  "Return t if the current line is the candidate for the last line of a comment, nil otherwise"
  (beginning-of-line)
  (looking-at ".*\\.[\t ]*$"))


(defun pspp-comment-p ()
  "Return t if point is in a comment.  Nil otherwise."
  ;; FIXME: Use `syntax-ppss'?
  (if (pspp-data-block-p)
      nil
    (let ((pspp-comment-start-found nil)
          (pspp-comment-end-found nil)
          (pspp-single-line-comment nil)
          (lines 1))
      (save-excursion
        (end-of-line)
        (while (and (>= lines 0)
                    (not pspp-comment-start-found)
                    (not pspp-comment-end-found))
          (beginning-of-line)
          (if (pspp-comment-start-line-p) (setq pspp-comment-start-found t))
          (if (bobp)
              (setq pspp-comment-end-found nil)
            (save-excursion
              (forward-line -1)
              (if (pspp-comment-end-line-p) (setq pspp-comment-end-found t))))
          (setq lines (forward-line -1))))

      (save-excursion
        (setq pspp-single-line-comment (and
                                        (pspp-comment-start-line-p)
                                        (pspp-comment-end-line-p))))

      (or pspp-single-line-comment
          (and pspp-comment-start-found (not pspp-comment-end-found))))))


(defvar pspp-mode-syntax-table
  (let ((st (make-syntax-table)))

    ;; Special chars allowed in variables
    (modify-syntax-entry ?#  "_" st)
    (modify-syntax-entry ?@  "_" st)
    (modify-syntax-entry ?$  "_" st)

    ;; Comment syntax
    ;;  This is incomplete, because:
    ;;  a) Comments can also be given by COMMENT
    ;;  b) The sequence .\n* is interpreted incorrectly.

    (modify-syntax-entry ?*  ". 2" st)
    (modify-syntax-entry ?.  ". 3" st)
    (modify-syntax-entry ?\n  "- 41" st)

    ;; String delimiters
    (modify-syntax-entry ?'  "\"" st)
    (modify-syntax-entry ?\"  "\"" st)

    st)

  "Syntax table for pspp-mode.")

(defconst pspp--syntax-propertize
  ;; FIXME: Properly handle comments!
  (syntax-propertize-rules
   ;; PSPP, like Pascal, uses '' and "" rather than \' and \" to escape quotes.
   ;; Code taken straight from `pascal.el'.
   ("''\\|\"\"" (0 (if (save-excursion
                         (nth 3 (syntax-ppss (match-beginning 0))))
                       (string-to-syntax ".")
                     ;; In case of 3 or more quotes in a row, only advance
                     ;; one quote at a time.
                     (forward-char -1)
                     nil)))))

(defconst pspp-font-lock-keywords
  (list (cons
         (concat "\\_<"
                 (regexp-opt (pspp--updown-list '(
                               "END DATA"
                               "ACF"
                               "ADD FILES"
                               "ADD VALUE LABELS"
                               "AGGREGATE"
                               "ANOVA"
                               "APPLY DICTIONARY"
                               "AREG"
                               "ARIMA"
                               "AUTORECODE"
                               "BEGIN DATA"
                               "BREAK"
                               "CASEPLOT"
                               "CASESTOVARS"
                               "CCF"
                               "CLEAR TRANSFORMATIONS"
                               "CLUSTER"
                               "COMPUTE"
                               "CONJOINT"
                               "CORRELATIONS"
                               "COXREG"
                               "COUNT"
                               "CREATE"
                               "CROSSTABS"
                               "CURVEFIT"
                               "DATA LIST"
                               "DATE"
                               "DEBUG CASEFILE"
                               "DEBUG EVALUATE"
                               "DEBUG MOMENTS"
                               "DEBUG POOL"
                               "DELETE VARIABLES"
                               "DESCRIPTIVES"
                               "DISCRIMINANT"
                               "DISPLAY"
                               "DOCUMENT"
                               "DO IF"
                               "DO REPEAT"
                               "DROP DOCUMENTS"
                               "ECHO"
                               "EDIT"
                               "ELSE"
                               "ELSE IF"
                               "END CASE"
                               "END FILE"
                               "END FILE TYPE"
                               "END IF"
                               "END INPUT PROGRAM"
                               "END LOOP"
                               "END REPEAT"
                               "ERASE"
                               "EXAMINE"
                               "EXECUTE"
                               "EXIT"
                               "EXPORT"
                               "FACTOR"
                               "FILE HANDLE"
                               "FILE LABEL"
                               "FILE TYPE"
                               "FILTER"
                               "FINISH"
                               "FIT"
                               "FLIP"
                               "FORMATS"
                               "FREQUENCIES"
                               "GENLOG"
                               "GET"
                               "GET TRANSLATE"
                               "GLM"
                               "GRAPH"
                               "HILOGLINEAR"
                               "HOST"
                               "IF"
                               "IGRAPH"
                               "IMPORT"
                               "INCLUDE"
                               "INFO"
                               "INPUT MATRIX"
                               "INPUT PROGRAM"
                               "KEYED DATA LIST"
                               "LEAVE"
                               "LIST"
                               "LOGLINEAR"
                               "LOGISITIC REGRESSION"
                               "LOOP"
                               "MATCH FILES"
                               "MATRIX DATA"
                               "MCONVERT"
                               "MEANS"
                               "MISSING VALUES"
                               "MODIFY VARS"
                               "MULT RESPONSE"
                               "MVA"
                               "NEW FILE"
                               "N"
                               "N OF CASES"
                               "NLR"
                               "NONPAR CORR"
                               "NPAR TESTS"
                               "NUMBERED"
                               "NUMERIC"
                               "OLAP CUBES"
                               "OMS"
                               "ONEWAY"
                               "ORTHOPLAN"
                               "PACF"
                               "PARTIAL CORR"
                               "PEARSON CORRELATIONS"
                               "PERMISSIONS"
                               "PLOT"
                               "POINT"
                               "PPLOT"
                               "PREDICT"
                               "PRESERVE"
                               "PRINT EJECT"
                               "PRINT"
                               "PRINT FORMATS"
                               "PRINT SPACE"
                               "PROCEDURE OUTPUT"
                               "PROXIMITIES"
                               "Q"
                               "QUICK CLUSTER"
                               "QUIT"
                               "RANK"
                               "RECODE"
                               "RECORD TYPE"
                               "REFORMAT"
                               "REGRESSION"
                               "RENAME VARIABLES"
                               "REPEATING DATA"
                               "REPORT"
                               "REREAD"
                               "RESTORE"
                               "RMV"
                               "SAMPLE"
                               "SAVE"
                               "SAVE TRANSLATE"
                               "SCRIPT"
                               "SELECT IF"
                               "SET"
                               "SHOW"
                               "SORT CASES"
                               "SORT"
                               "SPCHART"
                               "SPLIT FILE"
                               "STRING"
                               "SUBTITLE"
                               "SUMMARIZE"
                               "SURVIVAL"
                               "SYSFILE INFO"
                               "TEMPORARY"
                               "TITLE"
                               "TSET"
                               "TSHOW"
                               "TSPLOT"
                               "T-TEST"
                               "UNIANOVA"
                               "UNNUMBERED"
                               "UPDATE"
                               "USE"
                               "VALUE LABELS"
                               "VARIABLE ALIGNMENT"
                               "VARIABLE LABELS"
                               "VARIABLE LEVEL"
                               "VARIABLE WIDTH"
                               "VARSTOCASES"
                               "VECTOR"
                               "VERIFY"
                               "WEIGHT"
                               "WRITE"
                               "WRITE FORMATS"
                               "XSAVE")) t) "\\_>")
         'font-lock-builtin-face)

        (cons
         (concat "\\_<" (regexp-opt (pspp--updown-list
                        '("ALL" "AND" "BY" "EQ" "GE" "GT" "LE" "LT" "NE" "NOT" "OR" "TO" "WITH"))
                        t) "\\_>")
         'font-lock-keyword-face)

        (cons
         (concat "\\_<"
                 (regexp-opt (pspp--updown-list '(
                               "ABS"
                               "ACOS"
                               "ANY"
                               "ANY"
                               "ARCOS"
                               "ARSIN"
                               "ARTAN"
                               "ASIN"
                               "ATAN"
                               "CDF.BERNOULLI"
                               "CDF.BETA"
                               "CDF.BINOM"
                               "CDF.BVNOR"
                               "CDF.CAUCHY"
                               "CDF.CHISQ"
                               "CDF.EXP"
                               "CDF.F"
                               "CDF.GAMMA"
                               "CDF.GEOM"
                               "CDF.HALFNRM"
                               "CDF.HYPER"
                               "CDF.IGAUSS"
                               "CDF.LAPLACE"
                               "CDF.LNORMAL"
                               "CDF.LOGISTIC"
                               "CDF.NEGBIN"
                               "CDF.NORMAL"
                               "CDF.PARETO"
                               "CDF.POISSON"
                               "CDF.RAYLEIGH"
                               "CDF.SMOD"
                               "CDF.SRANGE"
                               "CDF.T"
                               "CDF.T1G"
                               "CDF.T2G"
                               "CDF.UNIFORM"
                               "CDF.WEIBULL"
                               "CDFNORM"
                               "CFVAR"
                               "CONCAT"
                               "COS"
                               "CTIME.DAYS"
                               "CTIME.HOURS"
                               "CTIME.MINUTES"
                               "CTIME.SECONDS"
                               "DATE.DMY"
                               "DATE.MDY"
                               "DATE.MOYR"
                               "DATE.QYR"
                               "DATE.WKYR"
                               "DATE.YRDAY"
                               "EXP"
                               "IDF.BETA"
                               "IDF.CAUCHY"
                               "IDF.CHISQ"
                               "IDF.EXP"
                               "IDF.F"
                               "IDF.GAMMA"
                               "IDF.HALFNRM"
                               "IDF.IGAUSS"
                               "IDF.LAPLACE"
                               "IDF.LNORMAL"
                               "IDF.LOGISTIC"
                               "IDF.NORMAL"
                               "IDF.PARETO"
                               "IDF.RAYLEIGH"
                               "IDF.SMOD"
                               "IDF.SRANGE"
                               "IDF.T"
                               "IDF.T1G"
                               "IDF.T2G"
                               "IDF.UNIFORM"
                               "IDF.WEIBULL"
                               "INDEX"
                               "INDEX"
                               "LAG"
                               "LAG"
                               "LAG"
                               "LAG"
                               "LENGTH"
                               "LG10"
                               "LN"
                               "LNGAMMA"
                               "LOWER"
                               "LPAD"
                               "LPAD"
                               "LTRIM"
                               "LTRIM"
                               "MAX"
                               "MAX"
                               "MBLEN.BYTE"
                               "MEAN"
                               "MIN"
                               "MIN"
                               "MISSING"
                               "MOD"
                               "MOD10"
                               "NCDF.BETA"
                               "NCDF.CHISQ"
                               "NCDF.F"
                               "NCDF.T"
                               "NMISS"
                               "NORMAL"
                               "NPDF.BETA"
                               "NPDF.CHISQ"
                               "NPDF.F"
                               "NPDF.T"
                               "NUMBER"
                               "NVALID"
                               "PDF.BERNOULLI"
                               "PDF.BETA"
                               "PDF.BINOM"
                               "PDF.BVNOR"
                               "PDF.CAUCHY"
                               "PDF.CHISQ"
                               "PDF.EXP"
                               "PDF.F"
                               "PDF.GAMMA"
                               "PDF.GEOM"
                               "PDF.HALFNRM"
                               "PDF.HYPER"
                               "PDF.IGAUSS"
                               "PDF.LANDAU"
                               "PDF.LAPLACE"
                               "PDF.LNORMAL"
                               "PDF.LOG"
                               "PDF.LOGISTIC"
                               "PDF.NEGBIN"
                               "PDF.NORMAL"
                               "PDF.NTAIL"
                               "PDF.PARETO"
                               "PDF.POISSON"
                               "PDF.RAYLEIGH"
                               "PDF.RTAIL"
                               "PDF.T"
                               "PDF.T1G"
                               "PDF.T2G"
                               "PDF.UNIFORM"
                               "PDF.WEIBULL"
                               "PDF.XPOWER"
                               "PROBIT"
                               "RANGE"
                               "RANGE"
                               "RINDEX"
                               "RINDEX"
                               "RND"
                               "RPAD"
                               "RPAD"
                               "RTRIM"
                               "RTRIM"
                               "RV.BERNOULLI"
                               "RV.BETA"
                               "RV.BINOM"
                               "RV.CAUCHY"
                               "RV.CHISQ"
                               "RV.EXP"
                               "RV.F"
                               "RV.GAMMA"
                               "RV.GEOM"
                               "RV.HALFNRM"
                               "RV.HYPER"
                               "RV.IGAUSS"
                               "RV.LANDAU"
                               "RV.LAPLACE"
                               "RV.LEVY"
                               "RV.LNORMAL"
                               "RV.LOG"
                               "RV.LOGISTIC"
                               "RV.LVSKEW"
                               "RV.NEGBIN"
                               "RV.NORMAL"
                               "RV.NTAIL"
                               "RV.PARETO"
                               "RV.POISSON"
                               "RV.RAYLEIGH"
                               "RV.RTAIL"
                               "RV.T"
                               "RV.T1G"
                               "RV.T2G"
                               "RV.UNIFORM"
                               "RV.WEIBULL"
                               "RV.XPOWER"
                               "SD"
                               "SIG.CHISQ"
                               "SIG.F"
                               "SIN"
                               "SQRT"
                               "STRING"
                               "SUBSTR"
                               "SUBSTR"
                               "SUM"
                               "SYSMIS"
                               "SYSMIS"
                               "TAN"
                               "TIME.DAYS"
                               "TIME.HMS"
                               "TRUNC"
                               "UNIFORM"
                               "UPCASE"
                               "VALUE"
                               "VARIANCE"
                               "XDATE.DATE"
                               "XDATE.HOUR"
                               "XDATE.JDAY"
                               "XDATE.MDAY"
                               "XDATE.MINUTE"
                               "XDATE.MONTH"
                               "XDATE.QUARTER"
                               "XDATE.SECOND"
                               "XDATE.TDAY"
                               "XDATE.TIME"
                               "XDATE.WEEK"
                               "XDATE.WKDAY"
                               "XDATE.YEAR"
                               "YRMODA"))
                             t) "\\_>")  'font-lock-function-name-face)

        ;; FIXME: The doc at
        ;; https://www.gnu.org/software/pspp/manual/html_node/Tokens.html
        ;; does not include `$' in the allowed first chars and it includes
        ;; `. $ # @' additionally to `_' in the subsequent chars.
        '( "\\_<[#$@[:alpha:]][[:alnum:]_]*\\_>"
           . font-lock-variable-name-face))
  "Highlighting expressions for PSPP mode.")


;;;###autoload
(define-derived-mode pspp-mode prog-mode "PSPP"
  "Major mode to edit PSPP files."
  (set (make-local-variable 'font-lock-keywords-case-fold-search) t)
  (set (make-local-variable 'font-lock-defaults) '(pspp-font-lock-keywords))

  (set (make-local-variable 'indent-line-function) #'pspp-indent-line)
  (set (make-local-variable 'comment-start) "* ")
  (set (make-local-variable 'compile-command)
       (concat "pspp "
               buffer-file-name))

  (set (make-local-variable 'syntax-propertize-function)
       pspp--syntax-propertize))

(provide 'pspp-mode)

;;; pspp-mode.el ends here
