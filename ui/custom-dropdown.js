/**
 * Custom Dropdown - Minimal replacement for broken native <select>
 * Inherits all styles from the original select element
 *
 * Usage: <select data-custom-dropdown>...</select>
 */

class CustomDropdown {
    constructor(selectElement) {
        this.select = selectElement;
        this.isOpen = false;
        this.init();
    }

    init() {
        if (this.select.options.length === 0) return;

        const selectStyles = window.getComputedStyle(this.select);

        this.container = document.createElement('div');
        this.container.className = 'custom-dropdown';
        this.container.style.cssText = `
            position: relative;
            width: ${selectStyles.width};
            display: ${selectStyles.display};
        `;

        const selected = document.createElement('div');
        selected.className = 'custom-dropdown-selected';
        selected.style.cssText = `
            background: ${selectStyles.background};
            border: ${selectStyles.border};
            padding: ${selectStyles.padding};
            color: ${selectStyles.color};
            font-size: ${selectStyles.fontSize};
            font-family: ${selectStyles.fontFamily};
            cursor: pointer;
            user-select: none;
        `;
        selected.textContent = this.select.options[this.select.selectedIndex]?.text || '';

        const optionsContainer = document.createElement('div');
        optionsContainer.className = 'custom-dropdown-options';
        optionsContainer.style.cssText = `
            position: absolute;
            top: 100%;
            left: 0;
            right: 0;
            background: ${selectStyles.background || 'rgba(0, 0, 0, 0.95)'};
            border: ${selectStyles.border};
            border-top: none;
            max-height: 200px;
            overflow-y: auto;
            z-index: 1000;
            display: none;
        `;

        Array.from(this.select.options).forEach((option, index) => {
            const optionDiv = document.createElement('div');
            optionDiv.className = 'custom-dropdown-option';
            optionDiv.style.cssText = `
                padding: ${selectStyles.padding};
                color: ${selectStyles.color};
                font-size: ${selectStyles.fontSize};
                font-family: ${selectStyles.fontFamily};
                cursor: pointer;
            `;
            optionDiv.textContent = option.text;

            optionDiv.addEventListener('click', (e) => {
                e.stopPropagation();
                this.select.selectedIndex = index;
                selected.textContent = option.text;
                this.select.dispatchEvent(new Event('change', { bubbles: true }));
                this.close();
            });

            optionDiv.addEventListener('mouseenter', function() {
                this.style.filter = 'brightness(1.3)';
            });

            optionDiv.addEventListener('mouseleave', function() {
                this.style.filter = '';
            });

            optionsContainer.appendChild(optionDiv);
        });

        selected.addEventListener('click', (e) => {
            e.stopPropagation();
            this.toggle();
        });

        this.container.appendChild(selected);
        this.container.appendChild(optionsContainer);

        this.select.style.display = 'none';
        this.select.parentNode.insertBefore(this.container, this.select.nextSibling);

        this.selectedDisplay = selected;
        this.optionsContainer = optionsContainer;

        this.select.addEventListener('change', () => {
            this.selectedDisplay.textContent = this.select.options[this.select.selectedIndex]?.text || '';
        });
    }

    toggle() {
        this.isOpen = !this.isOpen;
        this.optionsContainer.style.display = this.isOpen ? 'block' : 'none';

        if (this.isOpen) {
            document.querySelectorAll('.custom-dropdown').forEach(dropdown => {
                if (dropdown !== this.container && dropdown._instance) {
                    dropdown._instance.close();
                }
            });
        }
    }

    close() {
        this.isOpen = false;
        this.optionsContainer.style.display = 'none';
    }

    static init(selector = '[data-custom-dropdown]') {
        document.querySelectorAll(selector).forEach(select => {
            if (!select._instance && select.options.length > 0) {
                const instance = new CustomDropdown(select);
                select._instance = instance;
                if (select.nextElementSibling?.classList.contains('custom-dropdown')) {
                    select.nextElementSibling._instance = instance;
                }
            }
        });

        if (!window._customDropdownInitialized) {
            window._customDropdownInitialized = true;

            document.addEventListener('click', (e) => {
                if (!e.target.closest('.custom-dropdown')) {
                    document.querySelectorAll('.custom-dropdown').forEach(dropdown => {
                        if (dropdown._instance) dropdown._instance.close();
                    });
                }
            });

            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    document.querySelectorAll('.custom-dropdown').forEach(dropdown => {
                        if (dropdown._instance) dropdown._instance.close();
                    });
                }
            });
        }
    }

    static refresh(selector = '[data-custom-dropdown]') {
        document.querySelectorAll(selector).forEach(select => {
            if (select._instance?.container) {
                select._instance.container.remove();
            }
            delete select._instance;
            // Reset display style in case it was hidden
            select.style.display = '';
        });
        CustomDropdown.init(selector);
    }
}

if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => CustomDropdown.init());
    } else {
        CustomDropdown.init();
    }
}

if (typeof window !== 'undefined') {
    window.CustomDropdown = CustomDropdown;
}
