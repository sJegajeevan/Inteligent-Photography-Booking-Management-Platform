'use client';

import React, { useState, useCallback } from 'react';
import { createPortal } from 'react-dom';

// Main Modal Component
const Modal = ({
  isOpen = false,
  onClose = () => {},
  title = '',
  children,
  footer = null,
  size = 'md',
  variant = 'default',
  closeButton = true,
  closeOnBackdrop = true,
  closeOnEscape = true,
  className = '',
  headerClassName = '',
  bodyClassName = '',
  footerClassName = '',
  ...props
}) => {
  // Handle escape key
  React.useEffect(() => {
    if (!isOpen || !closeOnEscape) return;

    const handleEscape = (e) => {
      if (e.key === 'Escape') {
        onClose();
      }
    };

    window.addEventListener('keydown', handleEscape);
    return () => window.removeEventListener('keydown', handleEscape);
  }, [isOpen, closeOnEscape, onClose]);

  // Prevent body scroll when modal is open
  React.useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = 'unset';
    }

    return () => {
      document.body.style.overflow = 'unset';
    };
  }, [isOpen]);

  // Size variants
  const sizeClasses = {
    sm: 'w-full max-w-sm',
    md: 'w-full max-w-md',
    lg: 'w-full max-w-lg',
    xl: 'w-full max-w-xl',
    '2xl': 'w-full max-w-2xl',
  };

  // Variant styles
  const variantClasses = {
    default: 'bg-white rounded-lg shadow-xl',
    info: 'bg-blue-50 border-2 border-blue-200 rounded-lg shadow-xl',
    success: 'bg-green-50 border-2 border-green-200 rounded-lg shadow-xl',
    warning: 'bg-yellow-50 border-2 border-yellow-200 rounded-lg shadow-xl',
    danger: 'bg-red-50 border-2 border-red-200 rounded-lg shadow-xl',
  };

  if (!isOpen) return null;

  const modalContent = (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4" {...props}>
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black bg-opacity-50 transition-opacity duration-300"
        onClick={closeOnBackdrop ? onClose : undefined}
      ></div>

      {/* Modal */}
      <div
        className={`
          relative bg-white rounded-lg shadow-2xl transform transition-all duration-300 
          ${sizeClasses[size]} ${variantClasses[variant]} ${className}
        `.trim()}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Close Button */}
        {closeButton && (
          <button
            onClick={onClose}
            className="absolute top-4 right-4 text-gray-500 hover:text-gray-700 transition duration-300 z-10"
            aria-label="Close modal"
          >
            <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
              <path
                fillRule="evenodd"
                d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                clipRule="evenodd"
              />
            </svg>
          </button>
        )}

        {/* Header */}
        {title && (
          <div
            className={`
              border-b border-gray-200 px-6 py-4 
              ${headerClassName}
            `.trim()}
          >
            <h2 className="text-xl font-bold text-gray-900">{title}</h2>
          </div>
        )}

        {/* Body */}
        <div
          className={`
            px-6 py-4 max-h-96 overflow-y-auto 
            ${bodyClassName}
          `.trim()}
        >
          {typeof children === 'string' ? (
            <p className="text-gray-700">{children}</p>
          ) : (
            children
          )}
        </div>

        {/* Footer */}
        {footer && (
          <div
            className={`
              border-t border-gray-200 px-6 py-4 bg-gray-50 rounded-b-lg 
              flex gap-3 justify-end
              ${footerClassName}
            `.trim()}
          >
            {footer}
          </div>
        )}
      </div>
    </div>
  );

  return typeof window !== 'undefined'
    ? createPortal(modalContent, document.body)
    : null;
};

// Alert Modal Component
export const AlertModal = ({
  isOpen = false,
  onClose = () => {},
  title = 'Alert',
  message = '',
  type = 'info', // 'info', 'success', 'warning', 'error'
  onConfirm = null,
  className = '',
}) => {
  const typeColors = {
    info: 'bg-blue-100 text-blue-800 border-blue-300',
    success: 'bg-green-100 text-green-800 border-green-300',
    warning: 'bg-yellow-100 text-yellow-800 border-yellow-300',
    error: 'bg-red-100 text-red-800 border-red-300',
  };

  const typeIcons = {
    info: (
      <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
        <path
          fillRule="evenodd"
          d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
          clipRule="evenodd"
        />
      </svg>
    ),
    success: (
      <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
        <path
          fillRule="evenodd"
          d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
          clipRule="evenodd"
        />
      </svg>
    ),
    warning: (
      <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
        <path
          fillRule="evenodd"
          d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
          clipRule="evenodd"
        />
      </svg>
    ),
    error: (
      <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
        <path
          fillRule="evenodd"
          d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
          clipRule="evenodd"
        />
      </svg>
    ),
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={title}
      size="md"
      className={className}
    >
      <div className="flex gap-4">
        <div className={`flex-shrink-0 ${typeColors[type]} p-3 rounded-lg`}>
          {typeIcons[type]}
        </div>
        <div className="flex-1">
          <p className="text-gray-700">{message}</p>
        </div>
      </div>

      <div className="mt-6 flex gap-3 justify-end">
        <button
          onClick={onClose}
          className="px-4 py-2 text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition duration-300 font-medium"
        >
          Close
        </button>
        {onConfirm && (
          <button
            onClick={() => {
              onConfirm();
              onClose();
            }}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition duration-300 font-medium"
          >
            Confirm
          </button>
        )}
      </div>
    </Modal>
  );
};

// Confirmation Modal Component
export const ConfirmModal = ({
  isOpen = false,
  onClose = () => {},
  onConfirm = () => {},
  title = 'Confirm Action',
  message = 'Are you sure you want to proceed?',
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  confirmButtonVariant = 'danger', // 'primary', 'danger', 'warning'
  loading = false,
  className = '',
}) => {
  const variantClasses = {
    primary: 'bg-blue-600 hover:bg-blue-700',
    danger: 'bg-red-600 hover:bg-red-700',
    warning: 'bg-yellow-600 hover:bg-yellow-700',
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} size="md" className={className}>
      <div className="py-4">
        <h3 className="text-lg font-bold text-gray-900 mb-2">{title}</h3>
        <p className="text-gray-600">{message}</p>
      </div>

      <div className="flex gap-3 justify-end mt-6">
        <button
          onClick={onClose}
          disabled={loading}
          className="px-4 py-2 text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition duration-300 font-medium disabled:opacity-50"
        >
          {cancelText}
        </button>
        <button
          onClick={onConfirm}
          disabled={loading}
          className={`
            px-4 py-2 text-white rounded-lg transition duration-300 font-medium 
            ${variantClasses[confirmButtonVariant]}
            disabled:opacity-50 disabled:cursor-not-allowed
            flex items-center gap-2
          `.trim()}
        >
          {loading && (
            <svg className="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" opacity="0.25"></circle>
              <path fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" opacity="0.75"></path>
            </svg>
          )}
          {confirmText}
        </button>
      </div>
    </Modal>
  );
};

// Form Modal Component
export const FormModal = ({
  isOpen = false,
  onClose = () => {},
  onSubmit = () => {},
  title = 'Form',
  children,
  submitText = 'Submit',
  cancelText = 'Cancel',
  loading = false,
  className = '',
}) => {
  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={title}
      size="md"
      className={className}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          onSubmit();
        }}
      >
        <div className="py-4">{children}</div>

        <div className="flex gap-3 justify-end mt-6">
          <button
            type="button"
            onClick={onClose}
            disabled={loading}
            className="px-4 py-2 text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition duration-300 font-medium disabled:opacity-50"
          >
            {cancelText}
          </button>
          <button
            type="submit"
            disabled={loading}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition duration-300 font-medium disabled:opacity-50 flex items-center gap-2"
          >
            {loading && (
              <svg className="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" opacity="0.25"></circle>
                <path fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" opacity="0.75"></path>
              </svg>
            )}
            {submitText}
          </button>
        </div>
      </form>
    </Modal>
  );
};

// useModal Hook
export const useModal = (initialState = false) => {
  const [isOpen, setIsOpen] = useState(initialState);

  const open = useCallback(() => setIsOpen(true), []);
  const close = useCallback(() => setIsOpen(false), []);
  const toggle = useCallback(() => setIsOpen((prev) => !prev), []);

  return { isOpen, open, close, toggle };
};

export default Modal;
