###
Docxgen.coffee
Created by Edgar HIPP
###

DocUtils=require('./docUtils')
ImgManager=require('./imgManager')
DocXTemplater=require('./docxTemplater')
JSZip=require('jszip')
fs= require('fs')

module.exports=class DocxGen
	templatedFiles=["word/document.xml","word/footer1.xml","word/footer2.xml","word/footer3.xml","word/header1.xml","word/header2.xml","word/header3.xml"]
	constructor: (content, @Tags={},@options) ->
		@setOptions(@options)
		@finishedCallback=()->
		@filesProcessed=0  # This is the number of files that were processed, When all files are processed and all qrcodes are decoded, the finished Callback is called
		@qrCodeNumCallBack=0 #This is the order of the qrcode
		@qrCodeWaitingFor= [] #The templater waits till all the qrcodes are decoded, This is the list of the remaining qrcodes to decode (only their order in the document is stored)
		if content? then if content.length>0 then @load(content)
	setOptions:(@options)->
		if @options?
			@intelligentTagging= if @options.intelligentTagging? then @options.intelligentTagging else on
			@qrCode= if @options.qrCode? then @options.qrCode else off
			if @qrCode==true then @qrCode=DocUtils.unsecureQrCode
			if @options.parser? then @parser=options.parser
		this
	loadFromFile:(path,options={})->
		@setOptions(options)
		promise=
			success:(fun)->
				this.successFun=fun
			successFun:()->
		if !options.docx? then options.docx=false
		if !options.async? then options.async=false
		if !options.callback? then options.callback=(rawData) =>
			@load rawData
			promise.successFun(this)
		DocUtils.loadDoc(path,options)
		if options.async==false then return this else return promise
	qrCodeCallBack:(num,add=true) ->
		if add==true
			@qrCodeWaitingFor.push num
		else if add == false
			index = @qrCodeWaitingFor.indexOf(num)
			@qrCodeWaitingFor.splice(index, 1)
		@testReady()
	testReady:()->
		if @qrCodeWaitingFor.length==0 and @filesProcessed== templatedFiles.length ## When all files are processed and all qrCodes are processed too, the finished callback can be called

			@ready=true
			@finishedCallback()
	getImageList:()-> @fileManager.getImageList()
	setImage: (path,data,options={}) ->
		if !options.binary? then options.binary=true
		@fileManager.setFile(path,data,options)

	load: (content)->
		@loadedContent=content
		@zip = new JSZip content
		@fileManager=(new FileManager(@zip)).loadFileRels()
		this
	applyTags:(@Tags=@Tags,qrCodeCallback=null)->
		#Loop inside all templatedFiles (basically xml files with content). Sometimes they dont't exist (footer.xml for example)
		for fileName in templatedFiles when !@zip.files[fileName]?
			@filesProcessed++ #count  files that don't exist as processed
		for fileName in templatedFiles when @zip.files[fileName]?
			currentFile= new DocXTemplater(@zip.files[fileName].asText(),{
				DocxGen:this
				Tags:@Tags
				intelligentTagging:@intelligentTagging
				qrCodeCallback:qrCodeCallback
				parser:@parser
			})

			@setData(fileName,currentFile.applyTags().content)
			@filesProcessed++
		#When all files have been processed, check if the document is ready
		@testReady()
	setData:(fileName,data,options={})->
		@zip.remove(fileName)
		@zip.file(fileName,data,options)
	getTags:()->
		usedTags=[]
		for fileName in templatedFiles when @zip.files[fileName]?
			currentFile= new DocXTemplater(@zip.files[fileName].asText(),{
				DocxGen:this
				Tags:@Tags
				intelligentTagging:@intelligentTagging
				parser:@parser
			})
			usedTemplateV= currentFile.applyTags().usedTags
			if DocUtils.sizeOfObject(usedTemplateV)
				usedTags.push {fileName,vars:usedTemplateV}
		usedTags
	setTags: (@Tags) ->
		this
	#output all files, if docx has been loaded via javascript, it will be available
	output: (options={}) ->
		if !options.download? then options.download=true
		if !options.name? then options.name="output.docx"
		if !options.type? then options.type="base64"
		result= @zip.generate({type:options.type})
		if options.download
			if DocUtils.env=='node'
				fs.writeFile process.cwd()+'/'+options.name, result, 'base64', (err) ->
					if err then throw err
					if options.callback? then options.callback()
			else
				#Be aware that data-uri doesn't work for too big files: More Info http://stackoverflow.com/questions/17082286/getting-max-data-uri-size-in-javascript
				document.location.href= "data:application/vnd.openxmlformats-officedocument.wordprocessingml.document;base64,#{result}"
		result
	getFullText:(path="word/document.xml") ->
		usedData=@zip.files[path].asText()
		(new DocXTemplater(usedData,{DocxGen:this,Tags:@Tags,intelligentTagging:@intelligentTagging})).getFullText()
	download: (swfpath, imgpath, filename="default.docx") ->
		output=@zip.generate()
		Downloadify.create 'downloadify',
			filename: () ->return filename
			data: () ->
				return output
			onCancel: () -> alert 'You have cancelled the saving of this file.'
			onError: () -> alert 'You must put something in the File Contents or there will be nothing to save!'
			swf: swfpath
			downloadImage: imgpath
			width: 100
			height: 30
			transparent: true
			append: false
			dataType:'base64'

