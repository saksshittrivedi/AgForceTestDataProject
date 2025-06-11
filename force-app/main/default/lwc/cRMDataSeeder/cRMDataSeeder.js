import { LightningElement, track } from 'lwc';
// import getAllObjects from '@salesforce/apex/TestDataCreationController.getAllSObjectNames';
import getFieldsForObject from '@salesforce/apex/TestDataCreationController.getFieldsForObject';
import callPromptBuilder from '@salesforce/apex/TestDataCreationController.callPromptBuilder';
import createTestData from '@salesforce/apex/TestDataCreationController.createTestData';
import getRecordTypesForObject from '@salesforce/apex/TestDataCreationController.getRecordTypesForObject';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class CRMDataSeeder extends NavigationMixin(LightningElement) {
    @track objectOptions = [];
    @track selectedObject = '';
    @track requiredFields = [];
    @track optionalFieldOptions = [];
    @track selectedOptionalFields = [];
    @track numberOfRecords = '';
    @track showFieldSelector = false;
    @track generatedPrompt;
    @track readOnlyPrompt = true;
    @track createTestDataButtonDisabled = true;
    @track generatePromptButtonDisabled = true;
    @track recordTypeOptions = [];
    @track selectedRecordTypeId = '';
    @track showRecordTypePicklist = false;

    objectToListMap = {
        'Account': 'Accounts_Created_Today',
        'Contact': 'Contacts_Created_Today',
        'Opportunity': 'Opportunities_Created_Today',
        'Lead': 'Lead_Created_Today',
        'Case': 'Cases_Created_Today'
    }
    // flowName = "Test_Data_Utility_Flow";
    // showFlow = false;
    // @track flowInputVariables = [];

    connectedCallback() {
        this.objectOptions = [
            { label: 'Account', value: 'Account' },
            { label: 'Contact', value: 'Contact' },
            { label: 'Opportunity', value: 'Opportunity' },
            { label: 'Lead', value: 'Lead' },
            { label: 'Case', value: 'Case' }
        ];

       this.toggleGeneratePromptButton();
        // const flow = this.template.querySelector('lightning-flow');
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.showFieldSelector = false;
   
        getFieldsForObject({ objectName: this.selectedObject })
            .then(result => {
                const { requiredFields, optionalFields } = result;

                // Make sure we convert to plain arrays
                const plainRequired = Array.isArray(requiredFields) ? [...requiredFields] : [];
                const plainOptional = Array.isArray(optionalFields) ? [...optionalFields] : [];

                this.requiredFields = plainRequired;

                // Construct label-value options for dual listbox
                const allFieldOptions = [...plainRequired, ...plainOptional].map(f => ({
                    label: f,
                    value: f
                }));

                this.optionalFieldOptions = allFieldOptions;

                console.log('✅ optionalFieldOptions:', JSON.stringify(this.optionalFieldOptions));

                // Select required fields by default in the dual list
                this.selectedOptionalFields = [...plainRequired];

                console.log('✅ selectedOptionalFields:', this.selectedOptionalFields);
                console.log('✅ requiredFields:', this.requiredFields);

                this.showFieldSelector = true;
                this.toggleGeneratePromptButton();
            })
            .catch(error => {
                console.error('❌ Error fetching fields:', error.body ? error.body.message : error.message);
            });

        getRecordTypesForObject({ objectApiName: this.selectedObject })
        .then(result => {
            if (result && result.length > 0) {
                this.recordTypeOptions = result;
                this.showRecordTypePicklist = true;
            } else {
                this.recordTypeOptions = [];
                this.selectedRecordTypeId = '';
                this.showRecordTypePicklist = false;
            }
        })
        .catch(error => {
            console.error('❌ Error fetching record types:', error);
            this.recordTypeOptions = [];
            this.selectedRecordTypeId = '';
            this.showRecordTypePicklist = false;
        });
           
    }

    handleFieldSelection(event) {
        this.selectedOptionalFields = Array.isArray(event.detail.value) ? [...event.detail.value] : [];
        console.log('🔍 Selected Fields (Required + Optional):', this.selectedOptionalFields);
        this.toggleGeneratePromptButton();
    }

    handleNumericChange(event) {
        this.numberOfRecords = parseInt(event.detail.value);
        console.log('🔢 Numeric value:', this.numberOfRecords);
        this.toggleGeneratePromptButton();
    }

    handlePromptChange(event){
        this.generatedPrompt = event.detail.value;
        this.toggleGeneratePromptButton();
    }

    handleRecordTypeChange(event) {
        this.selectedRecordTypeId = event.detail.value;
    }

    toggleGeneratePromptButton() {
        this.generatePromptButtonDisabled = !(
            this.selectedObject &&
            this.selectedOptionalFields.length > 0 &&
            this.numberOfRecords > 0 && this.numberOfRecords <= 100
        );
    }

   
    // toggleCreateTestDataButton() {
    //     this.createTestDataButtonDisabled = !(
    //         this.selectedObject &&
    //         this.selectedOptionalFields.length > 0 &&
    //         this.numberOfRecords &&
    //         this.generatedPrompt.length > 0
    //     );
    // }

    handleCreatePrompt(){
        if(!(
            this.selectedObject &&
            this.selectedOptionalFields.length > 0 &&
            this.numberOfRecords
        )) alert('Please fill values for all the inputs!');
        console.log("🚀 Button Clicked - Generate Prompt");
        this.createTestDataButtonDisabled = false;
        // this.generatePromptButtonDisabled = false;
       
        callPromptBuilder({
            objectApiName: this.selectedObject,
            numberOfRecords: this.numberOfRecords,
            fieldApiNames: this.selectedOptionalFields
        })
        .then(result => {
            if(result != null){
                this.generatedPrompt = result;
                console.log("prompt is ready");
                console.log("prompt:", this.generatedPrompt);
                this.readOnlyPrompt = false;
            }else{
                const errorShowToastEvent = new ShowToastEvent({
                    title: 'Error',
                    variant: 'Error',
                    message: result,
                    mode: 'sticky'
                });
                this.dispatchEvent(errorShowToastEvent);
            }
        })
        .catch( error =>{
            console.log("error occurred from callPromptBuilder -->"+error);
            const errorShowToastEvent = new ShowToastEvent({
                title: 'Error',
                variant: 'Error',
                message: error.body ? error.body.message : error.message,
                mode: 'sticky'
            });
            this.dispatchEvent(errorShowToastEvent);
        })
    }

    handleCreateTestData() {
        if(!(
            this.selectedObject &&
            this.selectedOptionalFields.length > 0 &&
            this.numberOfRecords &&
            this.generatedPrompt.length > 0
        )) alert('Please fill values for all the inputs!');
        console.log("🚀 Button Clicked - Create Test Data");
        this.createTestDataButtonDisabled = true;
       
        createTestData({
            promptInput: this.generatedPrompt,
            objectApiName: this.selectedObject,
            fieldApiNames: this.fieldApiNames,
            recordTypeId: this.selectedRecordTypeId
        })
        .then(result => {
            if(result === "success"){
                const numberOfRecordsString = this.numberOfRecords.toString();
                this[NavigationMixin.GenerateUrl]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: this.selectedObject,
                        actionName: 'list'
                    },
                    state: {
                        filterName: this.objectToListMap[this.selectedObject] // or 'AllAccounts' or any custom list view API name
                    }
                }).then(listViewUrl => {
                    const successToast = new ShowToastEvent({
                        title: 'Success',
                        variant: 'success',
                        message: '{0} records created successfully! {1}',
                        messageData: [
                            numberOfRecordsString,
                            {
                                url: listViewUrl,
                                label: 'Click to view.'
                            }
                        ],
                        mode: 'sticky'
                    });
                    this.dispatchEvent(successToast);
                });
            }else{
                const errorShowToastEvent = new ShowToastEvent({
                    title: 'Error',
                    variant: 'Error',
                    message: result,
                    mode: 'sticky'
                });
                this.dispatchEvent(errorShowToastEvent);
            }
        })
        .catch(error => {
            console.log("error occurred from createTestData -->"+error);
            const errorShowToastEvent = new ShowToastEvent({
                title: 'Error',
                variant: 'Error',
                message: error.body ? error.body.message : error.message,
                mode: 'sticky'
            });
            this.dispatchEvent(errorShowToastEvent);
        });        
    }
}