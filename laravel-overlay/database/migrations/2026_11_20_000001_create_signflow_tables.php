<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
 public function up(): void {
  Schema::create('companies',function(Blueprint $t){$t->id();$t->string('name');$t->foreignId('owner_id')->constrained('users');$t->timestamps();});
  Schema::create('company_user',function(Blueprint $t){$t->id();$t->foreignId('company_id')->constrained()->cascadeOnDelete();$t->foreignId('user_id')->constrained()->cascadeOnDelete();$t->string('role')->default('signer');$t->unique(['company_id','user_id']);$t->timestamps();});
  Schema::create('sign_documents',function(Blueprint $t){$t->id();$t->foreignId('company_id')->constrained()->cascadeOnDelete();$t->foreignId('created_by')->constrained('users');$t->string('title');$t->string('status')->default('draft');$t->timestamps();});
  Schema::create('sign_steps',function(Blueprint $t){$t->id();$t->foreignId('document_id')->constrained('sign_documents')->cascadeOnDelete();$t->foreignId('user_id')->constrained('users');$t->unsignedInteger('position');$t->string('status')->default('pending');$t->timestamp('signed_at')->nullable();$t->unique(['document_id','position']);$t->timestamps();});
  Schema::create('sign_events',function(Blueprint $t){$t->id();$t->foreignId('document_id')->constrained('sign_documents')->cascadeOnDelete();$t->foreignId('actor_id')->constrained('users');$t->string('action');$t->json('metadata')->nullable();$t->timestamps();});
 }
 public function down():void {foreach(['sign_events','sign_steps','sign_documents','company_user','companies'] as $table) Schema::dropIfExists($table);}
};
